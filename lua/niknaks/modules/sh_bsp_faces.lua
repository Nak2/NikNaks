-- Copyright © 2022-2072, Nak, https://steamcommunity.com/id/Nak2/
-- All Rights Reserved. Not allowed to be reuploaded.
-- License: https://github.com/Nak2/NikNaks/blob/main/LICENSE

local obj_tostring = "BSP %s [ %s ]"
local format = string.format

local meta = NikNaks.__metatables["BSP"]
local meta_face = {}
meta_face.__index = meta_face
meta_face.__tostring = function(self) return format( obj_tostring, "Faces", self.__id ) end
meta_face.MetaName = "BSP Faces"
NikNaks.__metatables["BSP Faces"] = meta_face

local MAX_MAP_FACES = 65536 
---Returns all faces. ( Warning, uses a lot of memory )
---@return table
function meta:GetFaces()
	if self._faces then return self._faces end
	self._faces = {}
	local data = self:GetLump( 7 )
	for i = 0, math.min(data:Size() / 448, MAX_MAP_FACES) - 1 do
		local t = {}
		t.plane 	= self:GetPlanes()[ data:ReadUShort() ]
		t.side 		= data:ReadByte() -- 1 = same direciton as face
		t.onNode 	= data:ReadByte() -- 1 if on node, 0 if in leaf
		t.firstedge = data:ReadLong()
		t.numedges 	= data:ReadShort()
		t.texinfo 	= data:ReadShort() -- Texture info
		t.dispinfo	= data:ReadShort() -- Displacement info
		t.surfaceFogVolumeID	= data:ReadShort()
		t.styles				= {data:ReadByte(), data:ReadByte(), data:ReadByte(), data:ReadByte()}
		t.lightofs				= data:ReadLong()
		t.area					= data:ReadFloat()
		t.LightmapTextureMinsInLuxels	= {data:ReadLong(), data:ReadLong()}
		t.LightmapTextureSizeInLuxels	= {data:ReadLong(), data:ReadLong()}
		t.origFace			= data:ReadLong()
		t.numPrims			= data:ReadUShort()
		t.firstPrimID		= data:ReadUShort()
		t.smoothingGroups	= data:ReadULong()
		t.__bmodel = self:FindBModelIDByFaceIndex( i )
		t.__map = self
		t.__id = i
		setmetatable( t, meta_face )
		self._faces[i] = t
	end
	self:ClearLump( 7 )
	return self._faces
end

-- We make a small hack to cache and get the entities using brush-models.
local function __findEntityUsingBrush( self )
	if self.__funcBrush then return self.__funcBrush end
	local entities = self:GetEntities()
	self.__funcBrush = {[0] = entities[0]}
	for k, v in pairs( entities ) do
		local numMdl = string.match(v.model or "","*([%d]+)")
		if not numMdl then continue end
		self.__funcBrush[tonumber( numMdl )] = v
	end
	return self.__funcBrush
end

---Returns the face-index.
---@return number
function meta_face:GetIndex()
	return self.__id or -1
end
---Returns the normal for the face
---@return Vector
function meta_face:GetNormal()
	return self.plane.normal
end

---Returns the texture info for the face.
---@return table
function meta_face:GetTexInfo()
	return self.__map:GetTexInfo()[self.texinfo]
end

---Returns the texture data for the face.
---@return table
function meta_face:GetTexData()
	return self.__map:GetTexData()[ self:GetTexInfo().texdata ]
end

---Returns the texture for the face.
function meta_face:GetTexture()
	return self:GetTexData().nameStringTableID
end

---Returns the material the face use. Note: Materials within the BSP is not loaded.
---@return table
function meta_face:GetMaterial()
	if self._mat then return self._mat end
	self._mat = Material( self:GetTexture() or "__error" )
	return self._mat
end

---Returns true if the face should render.
---@return boolean
function meta_face:ShouldRender()
	local texinfo = self:GetTexInfo()
	local flags = texinfo and texinfo.flags or 0
	return bit.band(flags, 0x80) == 0 and bit.band(flags, 0x200) == 0
end

---Returns true if the face-texture is translucent
---@return boolean
function meta_face:IsTranslucent()
	local texinfo = self:GetTexInfo() or 0
	return bit.band(texinfo.flags, 0x10)~= 0
end

---Returns true if the face is part of 2D skybox.
---@return boolean
function meta_face:IsSkyBox()
	local texinfo = self:GetTexInfo() or 0
	return bit.band(texinfo.flags, 0x2)~= 0
end

---Returns true if the face is part of 3D skybox
---@return boolean
function meta_face:IsSkyBox3D()
	local texinfo = self:GetTexInfo() or 0
	return bit.band(texinfo.flags, 0x4)~= 0
end

---Returns true if the face's texinfo has said flag
---@return boolean
function meta_face:HasTexInfoFlag( flag )
	local texinfo = self:GetTexInfo() or 0
	return bit.band(texinfo.flags, flag)~= 0
end

---Returns true if the face is part of the world and not another entity.
---@return boolean
function meta_face:IsWorld()
	return self.__bmodel == 0
end

---Returns the BModel the face has. 0 if it is part of the world.
---@return number
function meta_face:GetBModel()
	return self.__bmodel
end

---Returns the entity-object-data that is part of this face.
---@return string EntityData
function meta_face:GetEntity()
	return __findEntityUsingBrush(self.__map)[self.__bmodel]
end

-- Displacments TODO: Fix Displacment Position and Data

---Returns true if the face is part of Displacment
---@return boolean
function meta_face:IsDisplacment()
	return self.dispinfo > -1
end

---Returns the vertex positions for the face. [Not Cached]
---Note this will ignore BModel-positions!
---@return table
function meta_face:GetVertexs()
	local t = {}
	if not self:IsDisplacment() then
		for i = 0, self.numedges - 1 do
			t[i + 1] = self.__map:GetSurfEdgesIndex( self.firstedge + i )
		end
		return t
	end
	-- This is a displacment
	-- TODO: Calculate the displacment mesh and return it here
end

---Returns a table in form of a polygon-mesh. [Not Cached]
---TAB[ID] = {pos = position, u = u, v = v, lu = lightU, lv = lightV }
---@return table
function meta_face:GenerateVertexData()
	local t = {}
	local tv = self:GetTexInfo().textureVects
	local lv = self:GetTexInfo().lightmapVecs
	local texdata = self:GetTexData()
	local mat_w, mat_h = texdata.view_width, texdata.view_height
	local n = self:GetNormal()

	-- Move the faces to match func_brushes (If any)
	local bNum = self.__bmodel
	local exPos, exAng
	if bNum > 0 then
		-- Get funch_brushes and their location
		local func_brush = __findEntityUsingBrush(self.__map)[bNum]
		if func_brush then
			exPos = func_brush.origin
			exAng = func_brush.angles
		end
	end

	for i = 0, self.numedges - 1 do
		local vert = {}
		local a = self.__map:GetSurfEdgesIndex( self.firstedge + i )
		vert.pos = a
		if bNum > 0 then -- WorldPos -> Entity Brush
			a = WorldToLocal( a, Angle(0,0,0), Vector(0,0,0), exAng )
			vert.pos = a + exPos
		end
		vert.normal = n
		-- UV & LV
		vert.u = ( tv[0][0] * a.x + tv[0][1] * a.y + tv[0][2] * a.z + tv[0][3] ) / mat_w
		vert.v = ( tv[1][0] * a.x + tv[1][1] * a.y + tv[1][2] * a.z + tv[1][3] ) / mat_h

		vert.lu = self.LightmapTextureMinsInLuxels[1] - ( lv[0][0] * a.x + lv[0][1] * a.y + lv[0][2] * a.z + lv[0][3] )
		vert.lv = self.LightmapTextureMinsInLuxels[2] - ( lv[1][0] * a.x + lv[1][1] * a.y + lv[1][2] * a.z + lv[1][3] )

		vert.userdata = { 0, 0, 0, 0 } -- Todo: Calculate this?

		t[i + 1] = vert
	end
	return t
end

local function PolyChop( o_vert )
	local vert = {}
	if #o_vert < 3 then return end
	local n, triCount = 1, #o_vert - 2
	for i = 1, triCount do
		vert[n] 	= o_vert[1]
		vert[n + 1] = o_vert[i + 1]
		vert[n + 2] = o_vert[i + 2]
		n = n + 3
	end
	return vert
end

---Returns a table in form of a polygon-mesh for triangles. [Not Cached]
---TAB[ID] = {pos = position, u = u, v = v, lu = lightU, lv = lightV }
---@return table
function meta_face:GenerateVertexTriangleData()
	return PolyChop( self:GenerateVertexData() )
end

---All mesh-data regarding said face. Should use face:GenerateVertexTriangleData intead!
---@return table
function meta_face:GenerateMeshData()
	local t = {}
	t.verticies = self:GenerateVertexData()
	t.triangles = PolyChop( t.verticies )
	t.material = self:GetTexture()
	return {t}
end

if CLIENT then
	NIKNAKS_TABOMESH = NIKNAKS_TABOMESH or {}
	---Builds the mesh if face has none.
	---@return iMesh
	function meta_face:BuildMesh()
		if SERVER then return end
		if self._mesh then return self._mesh end
		-- Tex
		local texinfo = self:GetTexInfo()
		if bit.band(texinfo.flags, 0x80) ~= 0 or bit.band(texinfo.flags, 0x200) ~= 0 then self._mesh = false return self._mesh end
		
		local meshData = self:GenerateVertexTriangleData()
		if not meshData then return self._mesh end
		self._mesh = Mesh( self:GetMaterial() )
		-- Vert
		mesh.Begin( self._mesh, MATERIAL_TRIANGLES, #meshData )
		for i = 1, #meshData do
			local vert = meshData[i]
			-- > Mesh
			mesh.Normal( vert.normal )
			mesh.Position( vert.pos ) -- Set the position
			mesh.TexCoord( 0, vert.u, vert.v ) -- Set the texture UV coordinates
			mesh.TexCoord( 1, vert.lu, vert.lv ) -- Set the lightmap UV coordinates
			mesh.TexCoord( 2, vert.lu, vert.lv  ) -- Set the lightmap UV coordinates
			--mesh.TexCoord( 2, self.LightmapTextureSizeInLuxels[1], self.LightmapTextureSizeInLuxels[2] ) -- Set the texture UV coordinates
			--mesh.TexCoord( 2, self.LightmapTextureMinsInLuxels[1], self.LightmapTextureMinsInLuxels[2] ) -- Set the texture UV coordinates
			mesh.AdvanceVertex()
		end
		mesh.End()
		table.insert(NIKNAKS_TABOMESH, self._mesh)
		return self._mesh
	end

	---Returns the mesh generated for the face.
	---Note. Need to call face:BuildMesh first.
	---@return iMesh|nil
	function meta_face:GetMesh()
		return self._mesh
	end

	---Deletes the mesh generated for the face.
	---@return self
	function meta_face:DeleteMesh()
		if not self._mesh then return end
		self._mesh:Destroy()
		self._mesh = nil
		return self
	end

	---Generates a mesh for the face and renders it.
	---@param dontGenerate boolean
	---@return boolean didGenerateMesh
	function meta_face:DebugRender( dontGenerate )
		local _mesh = self:GetMesh()
		if not _mesh and dontGenerate then return false end
		_mesh = _mesh or self:BuildMesh()
		if not IsValid(_mesh) then return end
		render.SetMaterial( self:GetMaterial() )
		_mesh:Draw()
		return true
	end
	for k, _mesh in pairs( NIKNAKS_TABOMESH ) do
		if IsValid(_mesh) then
			_mesh:Destroy()
		end
	end
end