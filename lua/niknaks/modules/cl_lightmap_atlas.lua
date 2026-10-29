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
]]

local byte, min, max, floor = string.byte, math.min, math.max, math.floor

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

local DEFAULT_WIDTH, DEFAULT_MAX_HEIGHT = 2048, 4096
local DEFAULT_SMOOTHING = 2
local DEFAULT_DESATURATE = 64

---@class LightmapAtlas
---@field private _rects table<number, table>
---@field private _lit table[]
---@field private _raw string
---@field private _width number
---@field private _height number
---@field private _scale number
---@field private _desaturate number
---@field private _progress fun( fraction: number )?
local atlas_meta = {}
atlas_meta.__index = atlas_meta
atlas_meta.MetaName = "LightmapAtlas"
atlas_meta.__tostring = function( self )
	return string.format( "LightmapAtlas [ %dx%d, %d faces, x%d ]", self._width, self._height, #self._lit, self._scale )
end

---@class LightmapAtlasOptions
---@field hdr boolean? # Use the HDR lightmap. Default false.
---@field lightToggle (boolean|table<number, number>|fun( style: number ): number)? # Which light styles are added, as for MeshBuilderOptions.lightToggle. nil / true = the defaults, false = the first lightmap of a face only, a table or function (style -> weight, 0 = off, 1 = on) = your own.
---@field smoothing number? # Pixels a luxel is written as, interpolated between luxel centres so shadows have soft edges (1 = off, up to 4). A map that does not fit gets a smaller number. Default 2.
---@field width number? # Width of the atlas. A map that does not fit at a height of maxHeight gets one twice as wide. Default 2048.
---@field maxHeight number? # Tallest the atlas may be. Default 4096.
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

---@return fun( style: number ): number
local function weightFunction( lightToggle )
	if isfunction( lightToggle ) then return lightToggle end
	if istable( lightToggle ) then
		return function( style ) return lightToggle[style] or defaultWeight( style ) end
	end
	return defaultWeight
end

local function hasNoLight( lightofs, styles )
	if lightofs < 0 then return true end

	for slot = 1, SLOTS_PER_FACE do
		if styles[slot] ~= STYLE_UNUSED then return false end
	end
	return true
end

---A face has one lightmap per light style, one after the other. With bumped lighting each style is followed by 3 directional sets.
---@return table[]? slots # { start = position in the lump (1-based), weight }, nil if the face has no light
local function lightSlots( face, hdrFaces, addStyles, weightOf )
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

		slots[#slots + 1] = { start = lightofs + 1 + ( slot - 1 ) * stride, weight = addStyles and weightOf( style ) or 1 }
	end

	return #slots > 0 and slots or nil
end

local function collectLitFaces( faces, hdrFaces, addStyles, weightOf )
	local infos, seen = {}, 0

	-- bsp:GetFaces() starts at 0, so ipairs would skip the first face
	for _, face in pairs( faces ) do
		local slots = lightSlots( face, hdrFaces, addStyles, weightOf )
		if slots then
			infos[#infos + 1] = {
				face = face, slots = slots,
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

---Shelf packing. The first pixels are left for the white tile that faces without light point at.
---@return table rects # face id -> rectangle
---@return table lit # { face, slots, rect }
---@return number height # the texture height needed, a power of 2
local function packRects( infos, scale, maxWidth )
	local x, y, rowHeight = 2, 0, 1
	local rects, lit = {}, {}

	for i, info in ipairs( infos ) do
		local pw, ph = info.w * scale, info.h * scale
		if x + pw > maxWidth then x, y, rowHeight = 0, y + rowHeight, 0 end

		local rect = { x = x, y = y, w = info.w, h = info.h, pw = pw, ph = ph }
		rects[info.face.__id] = rect
		lit[i] = { face = info.face, slots = info.slots, rect = rect }

		x = x + pw + 1
		rowHeight = max( rowHeight, ph + 1 )
	end

	local needed = 1
	while needed < y + rowHeight do needed = needed * 2 end
	return rects, lit, needed
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

-- Decoding -------------------------------------------------------------------------------------------------------------

local lightR, lightG, lightB, lightValid = {}, {}, {}, {}
local fillAt, fillR, fillG, fillB = {}, {}, {}, {}

---Half of the color: the shader doubles the lightmap.
local function toPixel( light )
	return min( floor( 127.5 * ( light / 255 ) + 0.5 ), 255 )
end

---VRAD writes a luxel it has no sample for as black, or as a huge red with -rederrors.
local function isVRADError( r, g, b, scale )
	return ( r == 0 and g == 0 and b == 0 ) or ( g == 0 and b == 0 and r * scale > VRAD_ERROR_RED )
end

---A luxel is r, g, b and a signed exponent. The styles that are on are added in linear light, as the engine does.
local function sumStyles( raw, slots, offset )
	local lr, lg, lb = 0, 0, 0
	local present, valid = false, false

	for s = 1, #slots do
		local slot = slots[s]
		local base = slot.start + offset
		local r, g, b, exponent = byte( raw, base, base + 3 )

		if exponent then
			present = true
			if exponent > 127 then exponent = exponent - 256 end

			local scale = 2 ^ exponent / 255
			if not isVRADError( r, g, b, scale ) then
				valid = true
				local weighted = slot.weight * scale
				lr, lg, lb = lr + r * weighted, lg + g * weighted, lb + b * weighted
			end
		end
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

local function averageValidNeighbors( x, y, w, h )
	local sr, sg, sb, count = 0, 0, 0, 0

	for ny = max( y - 1, 0 ), min( y + 1, h - 1 ) do
		for nx = max( x - 1, 0 ), min( x + 1, w - 1 ) do
			local j = ny * w + nx + 1
			if lightValid[j] then sr, sg, sb, count = sr + lightR[j], sg + lightG[j], sb + lightB[j], count + 1 end
		end
	end

	return sr, sg, sb, count
end

---One pass fills the luxels next to valid ones. A few passes reach a few luxels deep.
---@return number filled
local function fillOnePass( w, h )
	local filled = 0

	for y = 0, h - 1 do
		for x = 0, w - 1 do
			local i = y * w + x + 1
			if not lightValid[i] then
				local sr, sg, sb, count = averageValidNeighbors( x, y, w, h )
				if count > 0 then
					filled = filled + 1
					fillAt[filled], fillR[filled], fillG[filled], fillB[filled] = i, sr / count, sg / count, sb / count
				end
			end
		end
	end

	for k = 1, filled do
		local i = fillAt[k]
		lightR[i], lightG[i], lightB[i], lightValid[i] = fillR[k], fillG[k], fillB[k], true
	end
	return filled
end

local function fillMissingLuxels( w, h )
	for _ = 1, FILL_PASSES do
		if fillOnePass( w, h ) == 0 then break end
	end

	for i = 1, w * h do
		if not lightValid[i] then lightR[i], lightG[i], lightB[i] = UNLIT, UNLIT, UNLIT end
	end
end

local function decodeFace( raw, slots, w, h, desaturate )
	for i = 0, w * h - 1 do
		local lr, lg, lb, present, valid = sumStyles( raw, slots, i * 4 )

		local r, g, b = UNLIT, UNLIT, UNLIT
		if present then r, g, b = toDisplayLight( lr, lg, lb, desaturate ) end

		lightR[i + 1], lightG[i + 1], lightB[i + 1], lightValid[i + 1] = r, g, b, valid
	end

	fillMissingLuxels( w, h )
end

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

local function samplePixel( x0, x1, tx, row0, row1, ty )
	local a, b, c, d = row0 + x0, row0 + x1, row1 + x0, row1 + x1
	return bilinear( lightR, a, b, c, d, tx, ty ), bilinear( lightG, a, b, c, d, tx, ty ), bilinear( lightB, a, b, c, d, tx, ty )
end

---Equal pixels in a row are drawn as one rectangle.
local function writeFace( rect, scale )
	local w, h, pw, ph = rect.w, rect.h, rect.pw, rect.ph

	for py = 0, ph - 1 do
		local y0, y1, ty = luxelPosition( py, scale, h )
		local row0, row1 = y0 * w + 1, y1 * w + 1

		local runStart, runR, runG, runB = 0, nil, nil, nil
		for px = 0, pw do
			local r, g, b
			if px < pw then
				local x0, x1, tx = luxelPosition( px, scale, w )
				r, g, b = samplePixel( x0, x1, tx, row0, row1, ty )
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

local function clearWithWhiteTile()
	render.Clear( 0, 0, 0, 255 )

	local white = toPixel( 255 )
	surface.SetDrawColor( white, white, white, 255 )
	surface.DrawRect( 0, 0, 1, 1 )
end

-- The atlas --------------------------------------------------------------------------------------------------------------

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

	local weightOf = weightFunction( options.lightToggle )
	local addStyles = options.lightToggle ~= false
	local infos = collectLitFaces( faces, hdr and bsp:GetFacesHDRLighting() or nil, addStyles, weightOf )
	if #infos == 0 then return nil, "none of the faces have light" end

	infos = sortTallestFirst( infos )
	pause()

	local packing, failure = choosePacking( infos, {
		smoothing = math.Clamp( options.smoothing or DEFAULT_SMOOTHING, 1, 4 ),
		width = options.width or DEFAULT_WIDTH,
		maxHeight = options.maxHeight or DEFAULT_MAX_HEIGHT,
	} )
	if not packing then return nil, failure end

	return setmetatable( {
		_raw = raw,
		_rects = packing.rects,
		_lit = packing.lit,
		_width = packing.width,
		_height = packing.height,
		_scale = packing.scale,
		_desaturate = options.desaturate or DEFAULT_DESATURATE,
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

---The number of faces that have light in the atlas.
---@return number
function atlas_meta:GetFaceCount()
	return #self._lit
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

---Writes the light into a render target. It is cleared first.
---@param rt ITexture # GetSize() big
function atlas_meta:Write( rt )
	local lit = self._lit
	local at, first = 1, true

	while first or at <= #lit do
		if self._progress then self._progress( at / max( #lit, 1 ) ) end

		render.PushRenderTarget( rt )
		cam.Start2D()
		if first then clearWithWhiteTile() first = false end

		local pixels = 0
		while at <= #lit and pixels < LUXELS_PER_STEP do
			local entry = lit[at]
			decodeFace( self._raw, entry.slots, entry.rect.w, entry.rect.h, self._desaturate )
			writeFace( entry.rect, self._scale )

			pixels = pixels + entry.rect.pw * entry.rect.ph
			at = at + 1
		end

		cam.End2D()
		render.PopRenderTarget()
		pause()
	end

	if self._progress then self._progress( 1 ) end
end

--- @class BSPObject
local meta = NikNaks.__metatables["BSP"]

--- Packs the baked light of faces into a render target of your own. Client only. See LightmapAtlas.
--- @param options LightmapAtlasOptions?
--- @param faces BSPFaceObject[]? # The faces to pack. Default: every face of the map.
--- @return LightmapAtlas? atlas # nil if there is no light, or it does not fit
--- @return string? failure
function meta:CreateLightmapAtlas( options, faces )
	return create( self, faces or self:GetFaces(), options )
end

--- Packs the baked light of faces into a render target of your own. Client only.
--- @overload fun( bsp: BSPObject, faces: BSPFaceObject[], options: LightmapAtlasOptions? ): LightmapAtlas?, string?
NikNaks.LightmapAtlas = setmetatable( { Create = create }, {
	__call = function( _, bsp, faces, options ) return create( bsp, faces, options ) end
} )
