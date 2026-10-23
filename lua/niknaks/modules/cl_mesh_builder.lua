-- Copyright © 2022-2072, Nak, https://steamcommunity.com/id/Nak2/
-- All Rights Reserved. Not allowed to be reuploaded.
-- License: https://github.com/Nak2/NikNaks/blob/main/LICENSE

--[[
	A small helper that compiles BSP faces into a set of meshes

		local builder = NikNaks.MeshBuilder()
		builder:AddFaces( faces, { light = true } )
		local object = builder:Build()

		hook.Add( "PostDrawOpaqueRenderables", "example", function( depth, skybox )
			if depth or skybox then return end
			object:Draw()          -- or object:Draw( matrix )
		end )

		object:Destroy()           -- when you are done with it
]]

---@class MeshBuilder
---@field private _batches table<string, { material: IMaterial, verts: PolygonMeshVertex[], colors: table[]?, n: number }>
---@field private _lightVerts PolygonMeshVertex[]
---@field private _lightColors table[]
local builder_meta = {}
builder_meta.__index = builder_meta
builder_meta.MetaName = "MeshBuilder"

---@class MeshObject
---@field private _meshes { material: IMaterial, mesh: IMesh }[]
---@field private _lightMeshes { material: IMaterial, mesh: IMesh }[]
---@field private _triangles number
local object_meta = {}
object_meta.__index = object_meta
object_meta.MetaName = "MeshObject"
object_meta.__tostring = function( self )
	return string.format( "MeshObject [ %d meshes, %d light meshes, %d triangles ]", #self._meshes, #self._lightMeshes, self._triangles )
end

-- Meshes can only hold so many vertices. This is a multiple of 3 and well under the limit.
local MAX_VERTS = 30000

-- Shaders that blend textures by the vertex data of a displacement
local BLEND_SHADERS = {
	WorldVertexTransition = true, -- the vertex alpha blends $basetexture into $basetexture2
	Lightmapped_4WayBlend = true, -- the vertex color / alpha are the weights of the 4 textures (the weights of lump 63)
}

---Does the material blend textures by the vertex data? GetShader() gives the implementation name, with the DirectX
---version in it ("WorldVertexTransition_DX9").
---@param material IMaterial
---@return boolean
local function blendsTextures( material )
	return BLEND_SHADERS[( string.gsub( material:GetShader(), "_DX%d+$", "" ) )] == true
end

---Builds one mesh from verts[first..last] (a multiple of 3 vertices).
local function buildMesh( material, verts, colors, first, last, us, vs )
	local m = Mesh( material )
	mesh.Begin( m, MATERIAL_TRIANGLES, ( last - first + 1 ) / 3 )
	for i = first, last do
		local v = verts[i]
		local c = colors and colors[i]
		mesh.Normal( v.normal )
		mesh.Position( v.pos )
		if c then mesh.Color( c.r, c.g, c.b, c.a or 255 ) else mesh.Color( 255, 255, 255, 255 ) end
		mesh.TexCoord( 0, v.u, v.v )
		if us then
			-- Own lightmap coordinates (the faces are not changed). Stage 2 is the offset between the bump sets of the
			-- lightmap: none, so a bumped material reads the same light for each.
			mesh.TexCoord( 1, us[i], vs[i] )
			mesh.TexCoord( 2, 0, 0 )
		else
			mesh.TexCoord( 1, v.u1, v.v1 )
		end
		mesh.AdvanceVertex()
	end
	mesh.End()
	return m
end

-- Bits of $flags (MATERIAL_VAR_ADDITIVE = 1 << 7, MATERIAL_VAR_TRANSLUCENT = 1 << 21)
local MATERIAL_VAR_ADDITIVE_BIT = 0x80
local MATERIAL_VAR_TRANSLUCENT_BIT = 0x200000

---Does the material blend with what is behind it ($translucent or $additive)? Those must not write depth when drawn:
---a window would otherwise cut out everything behind it that is drawn later. Alpha tested materials (fences, leaves)
---are not these: their transparent pixels are discarded, so they are fine with depth.
---@param material IMaterial
---@return boolean
local function blendsWithBackground( material )
	-- $translucent and $additive are material flags: they are in $flags, and $translucent isn't always readable by name
	local flags = material:GetInt( "$flags" ) or 0
	if bit.band( flags, MATERIAL_VAR_TRANSLUCENT_BIT + MATERIAL_VAR_ADDITIVE_BIT ) ~= 0 then return true end
	return ( material:GetInt( "$translucent" ) or 0 ) ~= 0 or ( material:GetInt( "$additive" ) or 0 ) ~= 0
end

---Builds the meshes for a list of triangle vertices, split into chunks a mesh can hold.
---translucent: which pass the meshes belong to. nil = decided by the material.
local function buildChunks( material, verts, colors, out, us, vs, translucent )
	local total = #verts
	local pos = 1
	if translucent == nil then translucent = blendsWithBackground( material ) end
	while pos <= total do
		local last = math.min( pos + MAX_VERTS - 1, total )
		out[#out + 1] = { material = material, mesh = buildMesh( material, verts, colors, pos, last, us, vs ), translucent = translucent }
		pos = last + 1
	end
end

---Creates a new MeshBuilder.
---@return MeshBuilder
local function create()
	return setmetatable( { _batches = {}, _lightVerts = {}, _lightColors = {}, _lightVertsT = {}, _lightColorsT = {} }, builder_meta )
end

--- Creates a new MeshBuilder. Client only.
--- @overload fun(): MeshBuilder
NikNaks.MeshBuilder = setmetatable( { Create = create, BlendsWithBackground = blendsWithBackground }, {
	__call = function() return create() end
} )

---@class MeshBuilderOptions
---@field light boolean? # Add the baked lightmap as a second mesh, multiplied over the material when drawn. Faces without a lightmap are in it too, as white: unchanged, but they hide the light of faces behind them. Default false.
---@field hdr boolean? # Use the HDR lightmap. Default false.
---@field lightColors fun( face: BSPFaceObject, verts: PolygonMeshVertex[] ): table[]? # Your own light: a { r, g, b } (0-255) per vertex, used instead of the BSP lightmap. Return nil for no light on that face.
---@field material IMaterial? # Draw the faces with this material instead of their own, e.g. a flat material for a minimap.
---@field lightUV fun( face: BSPFaceObject, verts: PolygonMeshVertex[] ): number[], number[] # Your own lightmap coordinates, instead of the u1 / v1 of the vertices: returns two arrays (u and v), one number per vertex. For drawing with a lightmap of your own (MeshObjectDrawOptions.lightmap).

---Adds a face. Returns true if it was added.
---@param face BSPFaceObject
---@param options MeshBuilderOptions?
---@return boolean
function builder_meta:AddFace( face, options )
	local verts = face:GenerateVertexTriangleData()
	if not verts or #verts < 3 then return false end

	options = options or {}
	local material = options.material or face:GetMaterial()
	local key = material:GetName()

	local batch = self._batches[key]
	if not batch then
		batch = { material = material, verts = {}, n = 0 }
		self._batches[key] = batch
	end

	local list, n = batch.verts, batch.n
	for i = 1, #verts do list[n + i] = verts[i] end

	-- A displacement with a material that blends textures: the weights are in the color of its vertices, where the
	-- shader of the material reads them
	local blend = face:IsDisplacement() and blendsTextures( material )
	if blend or batch.colors then
		local colors = batch.colors
		if not colors then
			colors = {}
			for i = 1, n do colors[i] = color_white end
			batch.colors = colors
		end

		for i = 1, #verts do
			colors[n + i] = blend and verts[i].color or color_white
		end
	end
	-- Own lightmap coordinates. The vertices are the face's cache and are not changed: the numbers are kept beside them.
	if options.lightUV or batch.us then
		local us, vs = batch.us, batch.vs
		if not us then
			us, vs = {}, {}
			for i = 1, n do us[i], vs[i] = list[i].u1, list[i].v1 end
			batch.us, batch.vs = us, vs
		end

		local fu, fv
		if options.lightUV then fu, fv = options.lightUV( face, verts ) end
		for i = 1, #verts do
			us[n + i] = fu and fu[i] or verts[i].u1
			vs[n + i] = fv and fv[i] or verts[i].v1
		end
	end
	batch.n = n + #verts

	if options.light then
		local custom = options.lightColors
		local colors
		if custom then
			colors = custom( face, verts )
		else
			colors = face:GenerateLightColors( verts, options.hdr )
		end

		local lightVerts, lightColors = self._lightVerts, self._lightColors
		if blendsWithBackground( material ) then lightVerts, lightColors = self._lightVertsT, self._lightColorsT end
		local ln = #lightVerts
		for i = 1, #verts do
			lightVerts[ln + i] = verts[i]
			lightColors[ln + i] = colors and colors[i] or color_white
		end
	end

	return true
end

---Adds a list of faces. Returns how many were added.
---@param faces BSPFaceObject[]
---@param options MeshBuilderOptions?
---@return number
function builder_meta:AddFaces( faces, options )
	local added = 0
	for _, face in pairs( faces ) do
		if self:AddFace( face, options ) then added = added + 1 end
	end
	return added
end

---Compiles everything added so far into meshes. The builder is empty again afterwards.
---@return MeshObject
function builder_meta:Build()
	local object = setmetatable( { _meshes = {}, _lightMeshes = {}, _triangles = 0 }, object_meta )

	for _, batch in pairs( self._batches ) do
		buildChunks( batch.material, batch.verts, batch.colors, object._meshes, batch.us, batch.vs )
		object._triangles = object._triangles + batch.n / 3
	end
	local colorMaterial = Material( "color" )
	buildChunks( colorMaterial, self._lightVerts, self._lightColors, object._lightMeshes, nil, nil, false )
	buildChunks( colorMaterial, self._lightVertsT, self._lightColorsT, object._lightMeshes, nil, nil, true )

	self._batches, self._lightVerts, self._lightColors, self._lightVertsT, self._lightColorsT = {}, {}, {}, {}, {}
	return object
end

---@class MeshObjectDrawOptions
---@field light boolean? # Draw the light, if the object has any. Default true.
---@field fullbright boolean? # Draw the materials fullbright, so only the baked light shades them. Default true.
---@field ignoreZ boolean? # Draw on top of the world (clears the depth buffer first). Faces still sort against each other. Default false.
---@field lightOnly boolean? # Draw only the light colors, without the materials. Useful to check the light data. Default false.
---@field translucent boolean? # nil = draw all the meshes. false = only the opaque ones, true = only the ones that blend with the background ($translucent / $additive). Draw the opaque ones first with depth writing, the others last without it (render.OverrideDepthEnable( true, false )), so they don't cut out what is behind them.
---@field lightmap ITexture? # A lightmap texture of your own (see MeshBuilderOptions.lightUV). The materials of the map are then lit by it in one pass, with the normal lighting mode, and there is no light mesh and no nudge. Default nil.
---@field depthNudge number? # How far the light is moved toward the camera, as a fraction of the depth range (1 = not at all), so it passes the depth test against the materials. Default 0.9999. This is a fixed fraction, so it matters more the smaller or the further away the object is: if the step is too big, faces just behind a surface get their light on it too, and if it is too small the light flickers. For tiny objects use something like 0.999995.

local function drawPass( self, translucent, options )
	local meshes, lightMeshes = self._meshes, self._lightMeshes

	-- A translucent pass must not write depth, or a window would cut out what is drawn behind it afterwards
	if translucent then render.OverrideDepthEnable( true, false ) end

	if options.lightOnly then
		render.SetColorMaterial()
		for i = 1, #lightMeshes do
			local m = lightMeshes[i]
			if m.translucent == translucent then m.mesh:Draw() end
		end
	elseif options.lightmap then
		-- The materials use the lightmap given (their own shaders do the lighting)
		render.SetLightmapTexture( options.lightmap )
		for i = 1, #meshes do
			local m = meshes[i]
			if m.translucent == translucent then
				render.SetMaterial( m.material )
				m.mesh:Draw()
			end
		end
	else
		-- Fullbright only for the materials themselves, so it doesn't affect the light pass
		local fullbright = options.fullbright ~= false
		if fullbright then render.SetLightingMode( 1 ) end
		for i = 1, #meshes do
			local m = meshes[i]
			if m.translucent == translucent then
				render.SetMaterial( m.material )
				m.mesh:Draw()
			end
		end
		if fullbright then render.SetLightingMode( 0 ) end

		-- Multiply what was just drawn by the light color (dst * src), with the vertex color material of the engine.
		-- The depth range is nudged toward the camera, so the light wins the depth test against the first pass.
		if options.light ~= false and #lightMeshes > 0 then
			render.SetColorMaterial()
			render.OverrideBlend( true, BLEND_DST_COLOR, BLEND_ZERO, BLENDFUNC_ADD )
			render.DepthRange( 0, options.depthNudge or 0.9999 )
			for i = 1, #lightMeshes do
				local m = lightMeshes[i]
				if m.translucent == translucent then m.mesh:Draw() end
			end
			render.DepthRange( 0, 1 )
			render.OverrideBlend( false )
		end
	end

	if translucent then render.OverrideDepthEnable( false ) end
end

local function draw( self, matrix, options, opaque, translucent )
	options = options or {}
	if matrix then cam.PushModelMatrix( matrix ) end
	-- Only with the opaque pass: a translucent pass drawn on its own must keep the depth of what was drawn before it
	if opaque then
		if options.ignoreZ then render.ClearDepth() end
		drawPass( self, false, options )
	end
	if translucent then drawPass( self, true, options ) end
	if matrix then cam.PopModelMatrix() end
end

---Draws the object: the opaque meshes first, then the translucent ones (no depth writing). Call it from a 3D render hook,
---for example PostDrawOpaqueRenderables. Use options.translucent to draw only one of the two, or DrawOpaque / DrawTranslucent.
---@param matrix VMatrix?
---@param options MeshObjectDrawOptions?
function object_meta:Draw( matrix, options )
	local only = options and options.translucent
	draw( self, matrix, options, only ~= true, only ~= false )
end

---Draws only the opaque meshes (and their light). For PostDrawOpaqueRenderables.
---@param matrix VMatrix?
---@param options MeshObjectDrawOptions?
function object_meta:DrawOpaque( matrix, options )
	draw( self, matrix, options, true, false )
end

---Draws only the meshes that blend with the background ($translucent / $additive), without writing depth.
---Call it after the opaque pass, for example from PostDrawTranslucentRenderables. ignoreZ does not clear the depth here.
---@param matrix VMatrix?
---@param options MeshObjectDrawOptions?
function object_meta:DrawTranslucent( matrix, options )
	draw( self, matrix, options, false, true )
end

---Returns the compiled meshes, for drawing them yourself. Each entry is { material, mesh }.
---@return { material: IMaterial, mesh: IMesh }[]
function object_meta:GetMeshes()
	return self._meshes
end

---Returns the compiled light meshes. They use vertex colors, and are meant to be multiplied over the materials (drawn with render.SetColorMaterial()). Each entry is { material, mesh }.
---@return { material: IMaterial, mesh: IMesh }[]
function object_meta:GetLightMeshes()
	return self._lightMeshes
end

---Returns the number of triangles in the object (without the light).
---@return number
function object_meta:GetTriangleCount()
	return self._triangles
end

---Returns true if the object has not been destroyed.
---@return boolean
function object_meta:IsValid()
	return self._meshes ~= nil
end

---Frees the meshes. The object can't be drawn afterwards. Call this when you are done with it.
function object_meta:Destroy()
	if not self._meshes then return end
	for i = 1, #self._meshes do self._meshes[i].mesh:Destroy() end
	for i = 1, #self._lightMeshes do self._lightMeshes[i].mesh:Destroy() end
	self._meshes, self._lightMeshes, self._triangles = nil, nil, 0
end
