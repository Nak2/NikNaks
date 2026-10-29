-- Copyright © 2022-2072, Nak, https://steamcommunity.com/id/Nak2/
-- All Rights Reserved. Not allowed to be reuploaded.
-- License: https://github.com/Nak2/NikNaks/blob/main/LICENSE

--[[
	Packs the baked light of faces into a render target of your own, so the materials of the map can be lit by it in one pass.

		local atlas = bsp:CreateLightmapAtlas( { hdr = false }, faces ) -- faces defaults to every face of the map
		local width, height = atlas:GetSize()
		local rt = GetRenderTarget( "my_atlas", width, height )
		atlas:Write( rt )

		local builder = NikNaks.MeshBuilder()
		local options = { lightUV = atlas:GetLightUV() }
		builder:AddFaces( faces, options )
		local object = builder:Build()

		object:Draw( nil, { lightmap = rt } )

	Lights that flicker, pulse or are switched (animated light styles) only need to be named, and then updated:

		local atlas = bsp:CreateLightmapAtlas( { animatedStyles = { [1] = true, [2] = true } }, faces )
		atlas:Write( rt ) -- a second, smaller render target for the animated faces is made for you

		hook.Add( "Think", "example", function()
			atlas:Update( function( style ) return 0.5 + 0.5 * math.sin( CurTime() ) end ) -- style -> weight: 0 off, 1 on
		end )
]]

local byte, min, max, floor, abs = string.byte, math.min, math.max, math.floor, math.abs

local LUMP_LIGHTING, LUMP_LIGHTING_HDR = 8, 53
local SURF_BUMPLIGHT = 0x800
local STYLE_UNUSED = 255
local FIRST_SWITCHABLE_STYLE = 32
local SLOTS_PER_FACE = 4
local INV_GAMMA = 1 / 2.2
local MAX_DISPLAY_LIGHT = 510
local UNLIT = 255
local FILL_PASSES = 4
local VRAD_ERROR_RED = 100
local FACES_PER_YIELD = 2000
local LUXELS_PER_STEP = 30000
local FACES_PER_FLUSH_STEP = 64
local WEIGHT_EPSILON = 0.004

local DEFAULT_WIDTH, DEFAULT_MAX_HEIGHT, DEFAULT_LAYER_WIDTH = 2048, 4096, 1024
local DEFAULT_SMOOTHING = 2
local DEFAULT_DESATURATE = 64

---@class LightmapAtlas
---@field private _rects table<number, table>
---@field private _static table[] # faces written straight into the atlas
---@field private _animated table[] # faces made of a base and a layer per animated style
---@field private _styleEntries table<number, table[]> # animated style -> the faces that have it
---@field private _weights table<number, number> # animated style -> the weight drawn last
---@field private _dirty table<table, true>
---@field private _dirtyCount number
---@field private _raw string?
---@field private _width number
---@field private _height number
---@field private _layerWidth number?
---@field private _layerHeight number?
---@field private _scale number
---@field private _count number
---@field private _desaturate number
---@field private _initialWeights table|function|boolean|nil
---@field private _progress fun( fraction: number )?
local atlas_meta = {}
atlas_meta.__index = atlas_meta
atlas_meta.MetaName = "LightmapAtlas"
atlas_meta.__tostring = function( self )
	return string.format( "LightmapAtlas [ %dx%d, %d faces, %d animated, x%d ]", self._width, self._height, self._count, #self._animated, self._scale )
end

---@class LightmapAtlasOptions
---@field hdr boolean? # Use the HDR lightmap. Default false.
---@field lightToggle (boolean|table<number, number>|fun( style: number ): number)? # Which light styles are added, as for MeshBuilderOptions.lightToggle. nil / true = the defaults, false = the first lightmap of a face only, a table or function (style -> weight, 0 = off, 1 = on) = your own. For the animated styles this is the weight they start at.
---@field animatedStyles (table<number, boolean>|fun( style: number ): boolean)? # The styles whose weight will change after the atlas is written (SetStyleWeights). Faces with one get a layer each and are redrawn when it changes. Default none.
---@field smoothing number? # Pixels a luxel is written as, interpolated between luxel centres so shadows have soft edges (1 = off, up to 4). A map that does not fit gets a smaller number. Default 2.
---@field width number? # Width of the atlas. A map that does not fit at a height of maxHeight gets one twice as wide. Default 2048.
---@field maxHeight number? # Tallest the atlas may be. Default 4096.
---@field layerWidth number? # Width of the layers of the animated styles. Default 1024.
---@field desaturate number? # Light darker than this (0-255) fades to gray, which removes the colored speckles of dark areas. 0 = off. Default 64.
---@field progress fun( fraction: number )? # Called while Write runs, from 0 to 1.

---Yields when called inside a coroutine. Depending on how LuaJIT was built, coroutine.running() returns the main thread as well:
---then its second value says so.
local function pause()
	local thread, isMain = coroutine.running()
	if thread and not isMain then coroutine.yield() end
end

-- The light styles of a face -------------------------------------------------------------------------------------------

local function defaultWeight( style )
	if style > 0 and style < FIRST_SWITCHABLE_STYLE then return 0.5 end
	return 1
end

---@param weights boolean|table<number, number>|fun( style: number ): number|nil
local function weightOfStyle( weights, style )
	if isfunction( weights ) then return weights( style ) end
	if istable( weights ) then return weights[style] or defaultWeight( style ) end
	return defaultWeight( style )
end

local function animatedPredicate( animated, enabled )
	if not enabled or not animated then return function() return false end end
	if isfunction( animated ) then return animated end
	return function( style ) return animated[style] == true end
end

local function hasNoLight( lightofs, styles )
	if lightofs < 0 then return true end

	for slot = 1, SLOTS_PER_FACE do
		if styles[slot] ~= STYLE_UNUSED then return false end
	end
	return true
end

---A face has one lightmap per light style, one after the other. With bumped lighting each style is followed by 3 directional sets.
---@return table[]? slots # { start = position in the lump (1-based), style, weight }, nil if the face has no light
local function lightSlots( face, hdrFaces, addStyles, weights )
	local lightofs, styles = face.lightofs, face.styles
	if hdrFaces then
		local record = hdrFaces[face.__id]
		if not record then return nil end
		lightofs, styles = record.lightofs, record.styles
	end
	if hasNoLight( lightofs, styles ) then return nil end

	local sets = face:HasTexInfoFlag( SURF_BUMPLIGHT ) and 4 or 1
	local stride = ( face.LightmapTextureSizeInLuxels[1] + 1 ) * ( face.LightmapTextureSizeInLuxels[2] + 1 ) * 4 * sets

	local slots = {}
	for slot = 1, addStyles and SLOTS_PER_FACE or 1 do
		local style = styles[slot]
		if style == nil or style == STYLE_UNUSED then break end

		slots[#slots + 1] = {
			start = lightofs + 1 + ( slot - 1 ) * stride, style = style,
			weight = addStyles and weightOfStyle( weights, style ) or 1,
		}
	end

	return #slots > 0 and slots or nil
end

---@return table[] still # the slots that never change
---@return table[] moving # the slots of animated styles
local function splitSlots( slots, isAnimated )
	local still, moving = {}, {}
	for _, slot in ipairs( slots ) do
		if isAnimated( slot.style ) then moving[#moving + 1] = slot else still[#still + 1] = slot end
	end
	return still, moving
end

local function collectLitFaces( faces, hdrFaces, addStyles, weights, isAnimated )
	local infos, seen = {}, 0

	-- bsp:GetFaces() starts at 0, so ipairs would skip the first face
	for _, face in pairs( faces ) do
		local slots = lightSlots( face, hdrFaces, addStyles, weights )
		if slots then
			local still, moving = splitSlots( slots, isAnimated )
			infos[#infos + 1] = {
				face = face, slots = slots, still = still, moving = moving,
				w = face.LightmapTextureSizeInLuxels[1] + 1, h = face.LightmapTextureSizeInLuxels[2] + 1,
			}
		end

		seen = seen + 1
		if seen % FACES_PER_YIELD == 0 then pause() end
	end

	return infos
end

---Tallest first, so a row of short rectangles is not as tall as the one tall rectangle in it. Bucketed by height because
---sorting tens of thousands of faces in one step would hitch.
local function sortTallestFirst( infos )
	local byHeight, tallest = {}, 0
	for _, info in ipairs( infos ) do
		byHeight[info.h] = byHeight[info.h] or {}
		table.insert( byHeight[info.h], info )
		tallest = max( tallest, info.h )
	end

	local sorted = {}
	for height = tallest, 1, -1 do
		for _, info in ipairs( byHeight[height] or {} ) do sorted[#sorted + 1] = info end
	end
	return sorted
end

local function nextPowerOfTwo( n )
	local power = 1
	while power < n do power = power * 2 end
	return power
end

---Shelf packing: rows as tall as the tallest rectangle in them, one empty pixel between two rectangles.
---@param sizes { w: number, h: number }[]
---@param startX number # where the first row starts
---@return { x: number, y: number }[] positions
---@return number height # the texture height needed, a power of 2
local function shelfPack( sizes, maxWidth, startX )
	local x, y, rowHeight = startX, 0, 1
	local positions = {}

	for i, size in ipairs( sizes ) do
		if x + size.w > maxWidth then x, y, rowHeight = 0, y + rowHeight, 0 end

		positions[i] = { x = x, y = y }
		x = x + size.w + 1
		rowHeight = max( rowHeight, size.h + 1 )
	end

	return positions, nextPowerOfTwo( y + rowHeight )
end

---The first pixels are left for the white tile that faces without light point at.
---@return table rects # face id -> rectangle
---@return table lit # { face, slots, still, moving, w, h, rect }
---@return number height
local function packRects( infos, scale, maxWidth )
	local sizes = {}
	for i, info in ipairs( infos ) do sizes[i] = { w = info.w * scale, h = info.h * scale } end

	local positions, height = shelfPack( sizes, maxWidth, 2 )
	local rects, lit = {}, {}

	for i, info in ipairs( infos ) do
		local rect = { x = positions[i].x, y = positions[i].y, w = info.w, h = info.h, pw = sizes[i].w, ph = sizes[i].h }
		rects[info.face.__id] = rect
		lit[i] = { face = info.face, slots = info.slots, still = info.still, moving = info.moving, w = info.w, h = info.h, rect = rect }
	end

	return rects, lit, height
end

---The smoothing asked for, then smaller, and for a very big map a texture twice as wide.
local function packingConfigs( smoothing, width )
	local configs = {}
	for scale = smoothing, 1, -1 do configs[#configs + 1] = { scale, width } end
	configs[#configs + 1] = { 1, width * 2 }
	return configs
end

---@return table? packing
---@return string? failure
local function choosePacking( infos, options )
	local failure

	for _, config in ipairs( packingConfigs( options.smoothing, options.width ) ) do
		local scale, width = config[1], config[2]
		local rects, lit, height = packRects( infos, scale, width )
		if height <= options.maxHeight then
			return { rects = rects, lit = lit, width = width, height = height, scale = scale }
		end

		failure = string.format( "%d lit faces need %dx%d at scale %d", #infos, width, height, scale )
		pause()
	end

	return nil, failure
end

local function layerRectOf( position, entry )
	return { x = position.x, y = position.y, w = entry.w, h = entry.h, pw = entry.rect.pw, ph = entry.rect.ph }
end

---Each animated face gets a base (everything that never changes) and a delta per animated style in the layers, as big as its rectangle.
---@return number? width
---@return number? height # nil if they do not fit
local function layoutLayers( animated, width, maxHeight )
	if #animated == 0 then return nil end

	local sizes = {}
	for _, entry in ipairs( animated ) do
		for _ = 0, #entry.moving do sizes[#sizes + 1] = { w = entry.rect.pw, h = entry.rect.ph } end
	end

	local positions, height = shelfPack( sizes, width, 0 )
	if height > maxHeight then return nil end

	local at = 1
	for _, entry in ipairs( animated ) do
		entry.baseLayer, entry.deltaLayers = layerRectOf( positions[at], entry ), {}
		at = at + 1

		for k = 1, #entry.moving do
			entry.deltaLayers[k] = layerRectOf( positions[at], entry )
			at = at + 1
		end
	end

	return width, height
end

local function newImage()
	return { r = {}, g = {}, b = {} }
end

local baseImage = newImage()
local slotImages = { newImage(), newImage(), newImage(), newImage() }
local validMask, workMask = {}, {}
local slotR, slotG, slotB = {}, {}, {}
local fillAt, fillR, fillG, fillB = {}, {}, {}, {}

---Half of the color: the shader doubles the lightmap.
local function toPixel( light )
	return min( floor( 127.5 * ( light / 255 ) + 0.5 ), 255 )
end

---VRAD writes a luxel it has no sample for as black, or as a huge red with -rederrors.
local function isVRADError( r, g, b, scale )
	return ( r == 0 and g == 0 and b == 0 ) or ( g == 0 and b == 0 and r * scale > VRAD_ERROR_RED )
end

---A luxel is r, g, b and a signed exponent.
---@return number r # in linear light, times the weight
---@return number g
---@return number b
---@return boolean present
---@return boolean valid
local function readSlot( raw, start, weight, offset )
	local base = start + offset
	local r, g, b, exponent = byte( raw, base, base + 3 )
	if not exponent then return 0, 0, 0, false, false end

	if exponent > 127 then exponent = exponent - 256 end
	local scale = 2 ^ exponent / 255
	if isVRADError( r, g, b, scale ) then return 0, 0, 0, true, false end

	local weighted = weight * scale
	return r * weighted, g * weighted, b * weighted, true, true
end

---The styles that are on are added in linear light, as the engine does.
local function sumStyles( raw, slots, offset )
	local lr, lg, lb = 0, 0, 0
	local present, valid = false, false

	for s = 1, #slots do
		local slot = slots[s]
		local r, g, b, slotPresent, slotValid = readSlot( raw, slot.start, slot.weight, offset )
		lr, lg, lb = lr + r, lg + g, lb + b
		present = present or slotPresent
		valid = valid or slotValid
	end

	return lr, lg, lb, present, valid
end

---Scales the three channels together when the light is brighter than a lightmap can show, so a tinted light keeps its hue.
local function limitBrightness( r, g, b )
	local brightest = max( r, g, b )
	if brightest <= MAX_DISPLAY_LIGHT then return r, g, b end

	local factor = MAX_DISPLAY_LIGHT / brightest
	return r * factor, g * factor, b * factor
end

---A dim channel only has a few steps (the three share an exponent), and the gamma curve blows them up into colored speckles.
local function fadeDarkToGray( r, g, b, below )
	local top = max( r, g, b )
	if below <= 0 or top >= below then return r, g, b end

	local keep = top / below
	local gray = r * 0.299 + g * 0.587 + b * 0.114
	return gray + ( r - gray ) * keep, gray + ( g - gray ) * keep, gray + ( b - gray ) * keep
end

local function toDisplayLight( lr, lg, lb, desaturate )
	local r, g, b = limitBrightness( 255 * lr ^ INV_GAMMA, 255 * lg ^ INV_GAMMA, 255 * lb ^ INV_GAMMA )
	return fadeDarkToGray( r, g, b, desaturate )
end

local function averageValidNeighbors( image, mask, x, y, w, h )
	local sr, sg, sb, count = 0, 0, 0, 0

	for ny = max( y - 1, 0 ), min( y + 1, h - 1 ) do
		for nx = max( x - 1, 0 ), min( x + 1, w - 1 ) do
			local j = ny * w + nx + 1
			if mask[j] then sr, sg, sb, count = sr + image.r[j], sg + image.g[j], sb + image.b[j], count + 1 end
		end
	end

	return sr, sg, sb, count
end

---One pass fills the luxels next to valid ones. A few passes reach a few luxels deep.
---@return number filled
local function fillOnePass( image, mask, w, h )
	local filled = 0

	for y = 0, h - 1 do
		for x = 0, w - 1 do
			local i = y * w + x + 1
			if not mask[i] then
				local sr, sg, sb, count = averageValidNeighbors( image, mask, x, y, w, h )
				if count > 0 then
					filled = filled + 1
					fillAt[filled], fillR[filled], fillG[filled], fillB[filled] = i, sr / count, sg / count, sb / count
				end
			end
		end
	end

	for k = 1, filled do
		local i = fillAt[k]
		image.r[i], image.g[i], image.b[i], mask[i] = fillR[k], fillG[k], fillB[k], true
	end
	return filled
end

---Luxels with no sample are filled from the valid ones next to them. The mask is used up: pass a copy.
local function fillMissingLuxels( image, mask, w, h )
	for _ = 1, FILL_PASSES do
		if fillOnePass( image, mask, w, h ) == 0 then break end
	end

	for i = 1, w * h do
		if not mask[i] then image.r[i], image.g[i], image.b[i] = UNLIT, UNLIT, UNLIT end
	end
end

local function fillWithMaskCopy( image, w, h )
	for i = 1, w * h do workMask[i] = validMask[i] end
	fillMissingLuxels( image, workMask, w, h )
end

local function setLuxel( image, i, r, g, b )
	image.r[i], image.g[i], image.b[i] = r, g, b
end

local function decodeStaticFace( raw, entry, desaturate )
	local w, h = entry.w, entry.h

	for i = 0, w * h - 1 do
		local lr, lg, lb, present, valid = sumStyles( raw, entry.slots, i * 4 )

		if present then
			setLuxel( baseImage, i + 1, toDisplayLight( lr, lg, lb, desaturate ) )
		else
			setLuxel( baseImage, i + 1, UNLIT, UNLIT, UNLIT )
		end
		validMask[i + 1] = valid
	end

	fillWithMaskCopy( baseImage, w, h )
end

---The base is everything that never changes. For each animated style the image holds the light with that style at full weight;
---the difference to the base is what is drawn, times the weight, on top of it. That is exact at weight 0 and 1, and in between it
---mixes the encoded values, which is close enough for a flicker.
local function decodeAnimatedFace( raw, entry, desaturate )
	local w, h, moving = entry.w, entry.h, entry.moving

	for i = 0, w * h - 1 do
		local offset = i * 4
		local sr, sg, sb, present, valid = sumStyles( raw, entry.still, offset )

		for k, slot in ipairs( moving ) do
			local r, g, b, slotPresent, slotValid = readSlot( raw, slot.start, 1, offset )
			slotR[k], slotG[k], slotB[k] = r, g, b
			present = present or slotPresent
			valid = valid or slotValid
		end

		if present then
			setLuxel( baseImage, i + 1, toDisplayLight( sr, sg, sb, desaturate ) )
			for k = 1, #moving do
				setLuxel( slotImages[k], i + 1, toDisplayLight( sr + slotR[k], sg + slotG[k], sb + slotB[k], desaturate ) )
			end
		else
			setLuxel( baseImage, i + 1, UNLIT, UNLIT, UNLIT )
			for k = 1, #moving do setLuxel( slotImages[k], i + 1, UNLIT, UNLIT, UNLIT ) end
		end
		validMask[i + 1] = valid
	end

	fillWithMaskCopy( baseImage, w, h )
	for k = 1, #moving do
		local image = slotImages[k]
		fillWithMaskCopy( image, w, h )

		for i = 1, w * h do
			image.r[i] = max( image.r[i] - baseImage.r[i], 0 )
			image.g[i] = max( image.g[i] - baseImage.g[i], 0 )
			image.b[i] = max( image.b[i] - baseImage.b[i], 0 )
		end
	end
end

-- Writing -------------------------------------------------------------------------------------------------------------

---Pixel k of a rectangle is at luxel position ( k + 0.5 ) / scale - 0.5, so every luxel is interpolated between the centres.
local function luxelPosition( pixel, scale, size )
	local at = min( max( ( pixel + 0.5 ) / scale - 0.5, 0 ), size - 1 )
	local first = floor( at )
	return first, min( first + 1, size - 1 ), at - first
end

local function bilinear( light, a, b, c, d, tx, ty )
	local top = light[a] + ( light[b] - light[a] ) * tx
	local bottom = light[c] + ( light[d] - light[c] ) * tx
	return toPixel( top + ( bottom - top ) * ty )
end

local function samplePixel( image, x0, x1, tx, row0, row1, ty )
	local a, b, c, d = row0 + x0, row0 + x1, row1 + x0, row1 + x1
	return bilinear( image.r, a, b, c, d, tx, ty ), bilinear( image.g, a, b, c, d, tx, ty ), bilinear( image.b, a, b, c, d, tx, ty )
end

---Equal pixels in a row are drawn as one rectangle.
local function writeImage( rect, scale, image )
	local w, h, pw, ph = rect.w, rect.h, rect.pw, rect.ph

	for py = 0, ph - 1 do
		local y0, y1, ty = luxelPosition( py, scale, h )
		local row0, row1 = y0 * w + 1, y1 * w + 1

		local runStart, runR, runG, runB = 0, nil, nil, nil
		for px = 0, pw do
			local r, g, b
			if px < pw then
				local x0, x1, tx = luxelPosition( px, scale, w )
				r, g, b = samplePixel( image, x0, x1, tx, row0, row1, ty )
			end

			if px == pw or r ~= runR or g ~= runG or b ~= runB then
				if runR then
					surface.SetDrawColor( runR, runG, runB, 255 )
					surface.DrawRect( rect.x + runStart, rect.y + py, px - runStart, 1 )
				end
				runStart, runR, runG, runB = px, r, g, b
			end
		end
	end
end

local function clearTarget( rt, whiteTile )
	render.PushRenderTarget( rt )
	cam.Start2D()

	render.Clear( 0, 0, 0, 255 )
	if whiteTile then
		local white = toPixel( 255 )
		surface.SetDrawColor( white, white, white, 255 )
		surface.DrawRect( 0, 0, 1, 1 )
	end

	cam.End2D()
	render.PopRenderTarget()
end

---Draws entries in steps of about LUXELS_PER_STEP pixels, yielding between steps.
---@param drawEntry fun( entry: table ): number # returns the pixels it drew
local function writeInSteps( rt, entries, drawEntry, onEntry )
	local at = 1

	while at <= #entries do
		render.PushRenderTarget( rt )
		cam.Start2D()

		local pixels = 0
		while at <= #entries and pixels < LUXELS_PER_STEP do
			pixels = pixels + drawEntry( entries[at] )
			at = at + 1
			onEntry()
		end

		cam.End2D()
		render.PopRenderTarget()
		pause()
	end
end

local function writeStaticEntry( raw, scale, desaturate )
	return function( entry )
		decodeStaticFace( raw, entry, desaturate )
		writeImage( entry.rect, scale, baseImage )
		return entry.rect.pw * entry.rect.ph
	end
end

local function writeLayersOfEntry( raw, scale, desaturate )
	return function( entry )
		decodeAnimatedFace( raw, entry, desaturate )
		writeImage( entry.baseLayer, scale, baseImage )
		for k = 1, #entry.moving do writeImage( entry.deltaLayers[k], scale, slotImages[k] ) end

		return ( 1 + #entry.moving ) * entry.rect.pw * entry.rect.ph
	end
end

-- Compositing the animated faces ---------------------------------------------------------------------------------------

local function layerMaterial( rt, additive )
	local params = {
		["$basetexture"] = rt:GetName(), ["$vertexcolor"] = 1, ["$vertexalpha"] = 0, ["$ignorez"] = 1,
		["$nolod"] = 1, ["$nocull"] = 1, ["$pointsample"] = 1,
	}
	if additive then params["$additive"] = 1 end

	return CreateMaterial( "NikNaks_LightmapLayer_" .. ( additive and "add_" or "copy_" ) .. rt:GetName(), "UnlitGeneric", params )
end

---Draws a rectangle of the layers over a rectangle of the atlas, pixel for pixel.
local function drawLayerRect( layer, target, layerWidth, layerHeight )
	surface.DrawTexturedRectUV( target.x, target.y, target.pw, target.ph,
		layer.x / layerWidth, layer.y / layerHeight, ( layer.x + layer.pw ) / layerWidth, ( layer.y + layer.ph ) / layerHeight )
end

---The base, plus each delta times the weight of its style. A weight above 1 is drawn in more than one pass.
local function compositeEntry( atlas, entry )
	local layerWidth, layerHeight = atlas._layerWidth, atlas._layerHeight

	surface.SetMaterial( atlas._copyMaterial )
	surface.SetDrawColor( 255, 255, 255, 255 )
	drawLayerRect( entry.baseLayer, entry.rect, layerWidth, layerHeight )

	surface.SetMaterial( atlas._addMaterial )
	for k, slot in ipairs( entry.moving ) do
		local remaining = atlas._weights[slot.style] or 0

		while remaining > WEIGHT_EPSILON do
			local part = min( remaining, 1 )
			local level = floor( part * 255 + 0.5 )

			surface.SetDrawColor( level, level, level, 255 )
			drawLayerRect( entry.deltaLayers[k], entry.rect, layerWidth, layerHeight )
			remaining = remaining - part
		end
	end
end

local function markAllDirty( atlas )
	for _, entry in ipairs( atlas._animated ) do atlas._dirty[entry] = true end
	atlas._dirtyCount = #atlas._animated
end

-- The atlas --------------------------------------------------------------------------------------------------------------

local function indexStyles( animated )
	local byStyle = {}
	for _, entry in ipairs( animated ) do
		for _, slot in ipairs( entry.moving ) do
			byStyle[slot.style] = byStyle[slot.style] or {}
			table.insert( byStyle[slot.style], entry )
		end
	end
	return byStyle
end

---@param lit table[] # the faces with their rectangles
---@return table[] static
---@return table[] animated
local function splitEntries( lit )
	local static, animated = {}, {}
	for _, entry in ipairs( lit ) do
		if #entry.moving > 0 then animated[#animated + 1] = entry else static[#static + 1] = entry end
	end
	return static, animated
end

---Plans the atlas: which faces have light, and where each goes. Nothing is drawn until Write.
---@param bsp BSPObject
---@param faces BSPFaceObject[]
---@param options LightmapAtlasOptions?
---@return LightmapAtlas? atlas # nil if there is no light, or it does not fit
---@return string? failure
local function create( bsp, faces, options )
	options = options or {}

	local hdr = options.hdr == true
	local header = bsp._lumpheader[hdr and LUMP_LIGHTING_HDR or LUMP_LIGHTING]
	if not header or header.filelen <= 0 then return nil, "the map has no baked light" end

	local raw = bsp:GetLumpString( hdr and LUMP_LIGHTING_HDR or LUMP_LIGHTING )
	if #raw == 0 then return nil, "the map has no baked light" end

	local addStyles = options.lightToggle ~= false
	local isAnimated = animatedPredicate( options.animatedStyles, addStyles )
	local infos = collectLitFaces( faces, hdr and bsp:GetFacesHDRLighting() or nil, addStyles, options.lightToggle, isAnimated )
	if #infos == 0 then return nil, "none of the faces have light" end

	infos = sortTallestFirst( infos )
	pause()

	local packing, failure = choosePacking( infos, {
		smoothing = math.Clamp( options.smoothing or DEFAULT_SMOOTHING, 1, 4 ),
		width = options.width or DEFAULT_WIDTH,
		maxHeight = options.maxHeight or DEFAULT_MAX_HEIGHT,
	} )
	if not packing then return nil, failure end

	local static, animated = splitEntries( packing.lit )
	local layerWidth, layerHeight = layoutLayers( animated, options.layerWidth or DEFAULT_LAYER_WIDTH, options.maxHeight or DEFAULT_MAX_HEIGHT )

	-- The layers do not fit: the animated styles stay at the weight they start at
	if #animated > 0 and not layerWidth then
		for _, entry in ipairs( animated ) do static[#static + 1] = entry end
		animated = {}
	end

	return setmetatable( {
		_raw = raw,
		_rects = packing.rects,
		_static = static,
		_animated = animated,
		_styleEntries = indexStyles( animated ),
		_weights = {},
		_dirty = {},
		_dirtyCount = 0,
		_width = packing.width,
		_height = packing.height,
		_layerWidth = layerWidth,
		_layerHeight = layerHeight,
		_scale = packing.scale,
		_count = #packing.lit,
		_desaturate = options.desaturate or DEFAULT_DESATURATE,
		_initialWeights = options.lightToggle,
		_progress = options.progress,
	}, atlas_meta ), nil
end

---The size the render target needs to be.
---@return number width
---@return number height
---@return number smoothing # the pixels a luxel is written as: less than asked for if the map did not fit
function atlas_meta:GetSize()
	return self._width, self._height, self._scale
end

---The size the layers of the animated styles need to be.
---@return number? width # nil if no face has an animated style, or the layers did not fit
---@return number? height
function atlas_meta:GetLayerSize()
	return self._layerWidth, self._layerHeight
end

---The number of faces that have light in the atlas.
---@return number
function atlas_meta:GetFaceCount()
	return self._count
end

---The number of faces that change with their styles. 0 until Write has been given the layers.
---@return number
function atlas_meta:GetAnimatedFaceCount()
	return #self._animated
end

---Lightmap coordinates for MeshBuilderOptions.lightUV. Faces with light point at their rectangle, the others at a white tile (no change).
---@return fun( face: BSPFaceObject, verts: PolygonMeshVertex[] ): number[], number[]
function atlas_meta:GetLightUV()
	local rects, width, height, scale = self._rects, self._width, self._height, self._scale
	local whiteU, whiteV = 0.5 / width, 0.5 / height

	return function( face, verts )
		local rect = rects[face.__id]
		local us, vs = {}, {}

		for i, vertex in ipairs( verts ) do
			if rect then
				us[i] = ( rect.x + ( min( max( vertex.u1 * rect.w, 0 ), rect.w - 1 ) + 0.5 ) * scale ) / width
				vs[i] = ( rect.y + ( min( max( vertex.v1 * rect.h, 0 ), rect.h - 1 ) + 0.5 ) * scale ) / height
			else
				us[i], vs[i] = whiteU, whiteV
			end
		end

		return us, vs
	end
end

---Without layers the animated faces are written like the others, at the weight their styles start at.
local function makeAnimatedStatic( atlas )
	for _, entry in ipairs( atlas._animated ) do atlas._static[#atlas._static + 1] = entry end

	atlas._animated, atlas._styleEntries = {}, {}
	atlas._layerWidth, atlas._layerHeight = nil, nil
end

local function progressReporter( atlas, total )
	local done = 0
	return function()
		done = done + 1
		if atlas._progress then atlas._progress( min( done / max( total, 1 ), 1 ) ) end
	end
end

---A render target for the layers, named after the atlas so it is made once.
local function createLayerTarget( rt, width, height )
	local name = string.format( "%s_layers_%dx%d", rt:GetName(), width, height )
	return GetRenderTargetEx( name, width, height, RT_SIZE_LITERAL, MATERIAL_RT_DEPTH_NONE, 0, 0, IMAGE_FORMAT_RGBA8888 )
end

---Writes the light into a render target. It is cleared first. Can be called once.
---@param rt ITexture # GetSize() big
---@param layerRT (ITexture|false)? # GetLayerSize() big, for the faces of the animated styles. nil = one is made for you, false = none: the animated styles then stay at the weight they start at.
function atlas_meta:Write( rt, layerRT )
	if #self._animated > 0 then
		if layerRT == nil then layerRT = createLayerTarget( rt, self._layerWidth, self._layerHeight ) end
		if not layerRT then makeAnimatedStatic( self ) end
	end

	local raw, scale, desaturate = self._raw, self._scale, self._desaturate
	local onEntry = progressReporter( self, #self._static + #self._animated * 2 )

	clearTarget( rt, true )
	pause()

	if layerRT and #self._animated > 0 then
		clearTarget( layerRT, false )
		writeInSteps( layerRT, self._animated, writeLayersOfEntry( raw, scale, desaturate ), onEntry )
	end

	writeInSteps( rt, self._static, writeStaticEntry( raw, scale, desaturate ), onEntry )
	self._raw = nil

	if layerRT and #self._animated > 0 then
		self._rt = rt
		self._copyMaterial, self._addMaterial = layerMaterial( layerRT, false ), layerMaterial( layerRT, true )

		for style in pairs( self._styleEntries ) do self._weights[style] = weightOfStyle( self._initialWeights, style ) end
		markAllDirty( self )

		while self._dirtyCount > 0 do
			local before = self._dirtyCount
			self:Flush( FACES_PER_FLUSH_STEP )
			for _ = 1, before - self._dirtyCount do onEntry() end
			pause()
		end
	end

	-- Only what Flush needs is kept, not the faces and their slots
	self._static = {}
	for _, entry in ipairs( self._animated ) do entry.face, entry.slots, entry.still = nil, nil, nil end

	if self._progress then self._progress( 1 ) end
end

---Sets the weight of the animated styles. Faces whose weight changed are redrawn by Flush.
---@param weights table<number, number>|fun( style: number ): number # style -> weight, 0 = off, 1 = on, above 1 = brighter
---@return number changed # how many styles changed
function atlas_meta:SetStyleWeights( weights )
	local changed = 0

	for style, entries in pairs( self._styleEntries ) do
		local weight = weightOfStyle( weights, style )

		if abs( weight - ( self._weights[style] or 0 ) ) > WEIGHT_EPSILON then
			self._weights[style] = weight
			changed = changed + 1

			for _, entry in ipairs( entries ) do
				if not self._dirty[entry] then
					self._dirty[entry] = true
					self._dirtyCount = self._dirtyCount + 1
				end
			end
		end
	end

	return changed
end

---Redraws the faces whose styles changed, in no particular order. Call it every frame while it returns more than 0: a limit
---spreads a big change over several frames. It draws on the render target given to Write, so call it outside of other rendering (Think).
---@param maxFaces number? # Default 64
---@return number left # faces still waiting
function atlas_meta:Flush( maxFaces )
	if self._dirtyCount == 0 or not self._rt then return self._dirtyCount end

	maxFaces = maxFaces or FACES_PER_FLUSH_STEP
	local drawn = 0

	render.PushRenderTarget( self._rt )
	cam.Start2D()

	for entry in pairs( self._dirty ) do
		compositeEntry( self, entry )
		self._dirty[entry] = nil
		self._dirtyCount = self._dirtyCount - 1

		drawn = drawn + 1
		if drawn >= maxFaces then break end
	end

	cam.End2D()
	render.PopRenderTarget()

	return self._dirtyCount
end

---Sets the weights of the animated styles and redraws the faces that changed: SetStyleWeights and Flush in one. Call it every
---frame (Think); the weights are only compared, and a big change is spread over frames by maxFaces.
---@param weights table<number, number>|fun( style: number ): number # style -> weight, 0 = off, 1 = on, above 1 = brighter
---@param maxFaces number? # Faces redrawn per call. Default 64.
---@return number left # faces still waiting
function atlas_meta:Update( weights, maxFaces )
	self:SetStyleWeights( weights )
	return self:Flush( maxFaces )
end

---Does a face change with a style? False until Write has run, and when the layers did not fit.
---@return boolean
function atlas_meta:IsAnimated()
	return #self._animated > 0
end

--- @class BSPObject
local meta = NikNaks.__metatables["BSP"]

--- Packs the baked light of faces into a render target of your own. Client only. See LightmapAtlas.
--- @param options LightmapAtlasOptions?
--- @param faces BSPFaceObject[]? # The faces to pack. Default: every face of the map.
--- @return LightmapAtlas? atlas # nil if there is no light, or it does not fit
--- @return string? failure
function meta:CreateLightmapAtlas( options, faces )
	faces = faces or self:GetFaces()

	return create( self, faces, options )
end

--- Packs the baked light of faces into a render target of your own. Client only.
--- @overload fun( bsp: BSPObject, faces: BSPFaceObject[], options: LightmapAtlasOptions? ): LightmapAtlas?, string?
NikNaks.LightmapAtlas = setmetatable( { Create = create }, {
	__call = function( _, bsp, faces, options ) return create( bsp, faces, options ) end
} )
