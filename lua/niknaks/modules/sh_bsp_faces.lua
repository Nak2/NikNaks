-- Copyright © 2022-2072, Nak, https://steamcommunity.com/id/Nak2/
-- All Rights Reserved. Not allowed to be reuploaded.
-- License: https://github.com/Nak2/NikNaks/blob/main/LICENSE

local obj_tostring = "BSP %s [ %s ]"
local format = string.format

local vMeta = FindMetaTable("Vector")
local cross, dot = vMeta.Cross, vMeta.Dot

--- @class BSPObject
local meta = NikNaks.__metatables["BSP"]

--- @class BSPFaceObject
--- @field planenum number
--- @field plane BSPPlane
--- @field side number
--- @field onNode number
--- @field firstedge number
--- @field numedges number
--- @field texinfo number
--- @field dispinfo number
--- @field surfaceFogVolumeID number
--- @field styles table
--- @field lightofs number
--- @field area number
--- @field LightmapTextureMinsInLuxels table
--- @field LightmapTextureSizeInLuxels table
--- @field origFace number
--- @field numPrims number
--- @field firstPrimID number
--- @field smoothingGroups number
--- @field __bmodel number
--- @field __map BSPObject
--- @field __id number
--- @field _vertex table
local meta_face = {}
meta_face.__index = meta_face
meta_face.__tostring = function( self ) return format( obj_tostring, "Faces", self.__id ) end
meta_face.MetaName = "BSP Faces"
NikNaks.__metatables["BSP Faces"] = meta_face

local MAX_MAP_FACES = 65536

--- Returns all faces within the BSP. This is very memory intensive.
--- @return BSPFaceObject[]
function meta:GetFaces()
	if self._faces then return self._faces end
	self._faces = {}

	local data = self:GetLump( 7 )
	for i = 0, math.min( data:Size() / 448, MAX_MAP_FACES ) - 1 do
		--- @class BSPFaceObject
		local t = {}
		t.planenum = data:ReadUShort()
		t.plane 	= self:GetPlanes()[ t.planenum ]
		t.side 		= data:ReadByte() -- 1 = same direciton as face
		t.onNode 	= data:ReadByte() -- 1 if on node, 0 if in leaf
		t.firstedge = data:ReadLong()
		t.numedges 	= data:ReadShort()
		t.texinfo 	= data:ReadShort() -- Texture info
		t.dispinfo	= data:ReadShort() -- Displacement info
		t.surfaceFogVolumeID	= data:ReadShort()
		t.styles				= { data:ReadByte(), data:ReadByte(), data:ReadByte(), data:ReadByte() }
		t.lightofs				= data:ReadLong()
		t.area					= data:ReadFloat()
		t.LightmapTextureMinsInLuxels	= { data:ReadLong(), data:ReadLong() }
		t.LightmapTextureSizeInLuxels	= { data:ReadLong(), data:ReadLong() }
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

-- Returns the original face if found.
---@return OriginalFace?
function meta_face:GetOriginalFace()
	return self.__map:GetOriginalFaces()[self.origFace]
end

---Returns a list of faces that contain a displacment.
---@return BSPFaceObject[]
function meta:GetDisplacmentFaces()
	if self._distab then return self._distab end
	self._distab = {}
	for key, face in pairs(self:GetFaces()) do
		if(face.dispinfo == -1) then continue end
		table.insert(self._distab, face)
	end
	return self._distab
end

-- We make a small hack to cache and get the entities using brush-models.
local function __findEntityUsingBrush( self )
	if self.__funcBrush then return self.__funcBrush end

	local entities = self:GetEntities()
	self.__funcBrush = { [0] = entities[0] }

	for _, v in pairs( entities ) do
		local numMdl = string.match( v.model or "", "*([%d]+)" )

		if numMdl then
			self.__funcBrush[tonumber( numMdl )] = v
		end
	end

	return self.__funcBrush
end

--- Parses a Color object from the given BitBuffer
--- @param data BitBuffer
--- @return Color
local function __readColorRGBExp32 ( data )
	return NikNaks.ColorRGBExp32ToColor( {
		r = data:ReadByte(),
		g = data:ReadByte(),
		b = data:ReadByte(),
		exponent = data:ReadSignedByte()
	} )
end

--- Returns the lightmap samples for the face.
--- @return table<string, LightmapSample[]>?
function meta_face:GetLightmapSamples()
	local lightofs = self.lightofs

	if lightofs == -1 then return end
	if self._lightmap_samples then return self._lightmap_samples end

	--- @class LightmapSample
	--- @field color Color
	--- @field exponent number

	--- @type LightmapSample[]
	local full = {}

	--- @type LightmapSample[]
	local average = {}

	local samples = { average = average, full = full }
	self._lightmap_samples = samples

	local has_bumpmap = self:GetMaterial():GetString( "$bumpmap" ) ~= nil
	local luxel_count = ( self.LightmapTextureSizeInLuxels[1] + 1 ) * ( self.LightmapTextureSizeInLuxels[2] + 1 )

	local lightstyle_count = 0
	for _, v in ipairs( self.styles ) do
		if v ~= 255 then lightstyle_count = lightstyle_count + 1 end
	end

	-- "For faces with bumpmapped textures, there are four times the usual number of lightmap samples"
	local sample_count = lightstyle_count * luxel_count
	if has_bumpmap then sample_count = sample_count * 4 end

	local data = self.__map:GetLump( 8 )

	-- Get the average samples
	-- "Immediately preceeding the lightofs-referenced sample group,
	--  there are single samples containing the average lighting on the face, one for each lightstyle,
	--  in reverse order from that given in the styles[] array."
	local color, exponent
	data:Seek( ( lightofs * 8 ) - ( 32 * lightstyle_count ) )
	for _ = 1, lightstyle_count do
		color, exponent = __readColorRGBExp32( data )
		table.insert( average, 1, { color = color, exponent = exponent } )
	end

	-- Get the full samples
	for _ = 1, sample_count do
		color, exponent = __readColorRGBExp32( data )
		table.insert( full, { color = color, exponent = exponent } )
	end

	return samples
end

--- Returns the face-index. Will return -1 if none.
--- @return number
function meta_face:GetIndex()
	return self.__id or -1
end

--- Returns the normal vector for the face.
--- @return Vector
function meta_face:GetNormal()
	return self.plane.normal
end

--- Returns the texture info for the face.
--- @return TextureInfo?
function meta_face:GetTexInfo()
	return self.__map:GetTexInfo()[self.texinfo]
end

--- Returns the texture data for the face.
--- @return BSPTextureData?
function meta_face:GetTexData()
	return self.__map:GetTexData()[ self:GetTexInfo().texdata ]
end

--- Returns the texture for the face.
--- @return string
function meta_face:GetTexture()
	return self:GetTexData().nameStringTableID
end

--- Returns the material the face use. Note: Materials within the BSP won't be loaded.
--- @return IMaterial
function meta_face:GetMaterial()
	if self._mat then return self._mat end
	self._mat = Material( self:GetTexture() or "__error" )
	return self._mat
end

--- Returns true if the face should render.
--- @return boolean
function meta_face:ShouldRender()
	local texinfo = self:GetTexInfo()
	local flags = texinfo and texinfo.flags or 0
	return bit.band( flags, 0x80 ) == 0 and bit.band( flags, 0x200 ) == 0
end

--- Returns true if the face-texture is translucent
--- @return boolean
function meta_face:IsTranslucent()
	local texinfo = self:GetTexInfo() or 0
	return bit.band( texinfo.flags, 0x10 ) ~= 0
end

--- Returns true if the face is part of 2D skybox.
--- @return boolean
function meta_face:IsSkyBox()
	local texinfo = self:GetTexInfo() or 0
	return bit.band( texinfo.flags, 0x2 ) ~= 0
end

--- Returns true if the face is part of 3D skybox.
--- @return boolean
function meta_face:IsSkyBox3D()
	local texinfo = self:GetTexInfo() or 0
	return bit.band( texinfo.flags, 0x4 ) ~= 0
end

--- Returns true if the face's texinfo has said flag.
--- @return boolean
function meta_face:HasTexInfoFlag( flag )
	local texinfo = self:GetTexInfo() or 0
	return bit.band( texinfo.flags, flag  ) ~= 0
end

--- Returns true if the face is part of the world and not another entity.
--- @return boolean
function meta_face:IsWorld()
	return self.__bmodel == 0
end

--- Returns the BModel the face has. 0 if it is part of the world.
--- @return number
function meta_face:GetBModel()
	return self.__bmodel
end

--- Returns the entity-object-data that is part of this face.
--- @return string EntityData
function meta_face:GetEntity()
	return __findEntityUsingBrush( self.__map )[self.__bmodel]
end

-- Displacments TODO: Fix Displacment Position and Data

--- Returns true if the face is part of Displacment
--- @return boolean
function meta_face:IsDisplacement()
	return self.dispinfo > -1
end

--- Returns the DisplacmentInfo for the face.
---@return DispInfo
function meta_face:GetDisplacementInfo()
	local _, t = self.__map:GetDispInfo()
	return t[self.__id]
end

--- Returns the vertex positions for the face. [Not Cached]
--- Note this will ignore BModel-positions and displacment mesh.
--- @return Vector[]?
function meta_face:GetVertexs()
	if self._vertex then return self._vertex end
	local t = {}
	for i = 0, self.numedges - 1 do
		t[i + 1] = self.__map:GetSurfEdgesIndex( self.firstedge + i )
	end

	self._vertex = t
	return t
end

--- Checks to see if the triangle is intersecting and returns the intersection.
--- @param orig Vector
--- @param dir Vector
--- @param v0 Vector
--- @param v1 Vector
--- @param v2 Vector
--- @return Vector? intersectionPoint
--- @return number? distance
local function IsRayIntersectingTriangle(orig, dir, v0, v1, v2)
	local v0v1 = v1 - v0
	local v0v2 = v2 - v0
	local pvec = cross(dir,v0v2)
	local det = dot(v0v1, pvec)
	-- Ray and triangle are parallel if det is close to 0
	if det > -0.0001 and det < 0.0001 then
		return -- No intersection.
    end

	local invDet = 1 / det

	local tvec = orig - v0
	local u = dot(tvec, pvec) * invDet
	if (u < 0 or u > 1) then return end

	local qvec = cross(tvec,v0v1)
	local v = dot(dir, qvec) * invDet
	if (v < 0 or u + v > 1) then return end

	local t = dot(v0v2, qvec) * invDet
	if t > 0 then
		return orig + dir * t, t
	end

	return nil
end

--- Calculate the intersection point between a ray and the face.
--- @param origin Vector
--- @param dir Vector The normalized direction.
--- @return Vector? -- The intersection point if found, otherwise nil
--- @return number? distance
function meta_face:CalculateRayIntersection( origin, dir )
	if self.plane.normal:Dot( dir ) > 0 then return end
	local poly = self:GetVertexs()
	if not poly then return end
	for i = 1, #poly - 2 do
		local v0 = poly[1]
		local v1 = poly[i + 1]
		local v2 = poly[i + 2]
		local hitPos, dis = IsRayIntersectingTriangle(origin, dir, v0, v1, v2)

		if hitPos then
			return hitPos, dis
		end
	end
	return nil
end

--- Calculate the intersection point between a line segment and the face.
--- @param startPos Vector
--- @param endPos Vector
--- @return Vector? -- The in tersection point if found, otherwise nil
--- @return number? distance
function meta_face:CalculateSegmentIntersection( startPos, endPos )
	local plane = self.plane
	local dot1 = plane:DistTo(startPos)
	local dot2 = plane:DistTo(endPos)

	if (dot1 > 0) ~= (dot2 > 0) or true then
		local t = dot1 / ( dot1 - dot2 )

		if t <= 0 or t >= 1 then return end
		local poly = self:GetVertexs()
		if not poly then return end
		for i = 1, #poly - 2 do
            local v0 = poly[1]
            local v1 = poly[i + 1]
            local v2 = poly[i + 2]

            -- Check if ray is intersecting triangle point v0, v1 and v2
			local dir = (endPos - startPos):GetNormalized()
			local hitPos, dis = IsRayIntersectingTriangle(startPos, dir, v0, v1, v2)
            if hitPos then
				return hitPos, dis
			end
        end
	end
end

--- @class PolygonMeshVertex
--- @field normal Vector
--- @field pos Vector
--- @field u number
--- @field v number
--- @field lu number
--- @field lv number
--- @field tangent Vector
--- @field binormal Vector
--- @field userdata table<number, number>

--- @return PolygonMeshVertex[]
local function GetDisplacementVertexs(self, faceVertexData )
	local dispInfo = self:GetDisplacementInfo()
	local start = dispInfo.startPosition

	local baseVerts = faceVertexData
	assert( #baseVerts == 4 )

	---Extracts the u and v params from each point in vData and returns them as Vectors (u->x, v->y, z->0)
	local function extractUVVecs( vData, u, v )
		u = u or "u"
		v = v or "v"
		local uvs = {}

		local point
		for i = 1, #vData do
			point = vData[i]
			table.insert( uvs, Vector( point[u], point[v], 0 ) )
		end

		return unpack( uvs )
	end

	local baseQuad = {}
	local startIdx = 1
	do
		local minDist = math.huge

		local pos, idx, dist
		for i = 1, 4 do
			pos = baseVerts[i].pos
			idx = table.insert( baseQuad, pos ) --[[@as number]]

			dist = pos:Distance( start )
			if dist < minDist then
				minDist = dist
				startIdx = idx
			end
		end
	end

	local function rotated( q )
		local part = {}
		for i = startIdx, #q do
			table.insert( part, q[i] )
		end
		for i = 1, startIdx - 1 do
			table.insert( part, q[i] )
		end

		return part
	end

	local A, B, C, D = unpack( rotated( baseQuad ) )
	local AD = D - A
	local BC = C - B

	local quad = rotated( baseVerts )

	local uvA, uvB, uvC, uvD = extractUVVecs( quad )
	local uvAD = uvD - uvA
	local uvBC = uvC - uvB

	local uv2A, uv2B, uv2C, uv2D = extractUVVecs( quad, "u1", "v1" )
	local uv2AD = uv2D - uv2A
	local uv2BC = uv2C - uv2B

	local power = dispInfo.power
	local power2 = 2 ^ power
	local vertCount = ( ( 2 ^ power ) + 1 ) ^ 2
	local vertStart = dispInfo.DispVertStart
	local vertEnd = vertStart + vertCount

	local vertices = {}
	do
	    local LerpVector = LerpVector
	    local math_floor = math.floor
	    local table_insert = table.insert

		local dispVertices = self.__map:GetDispVerts()
		local vertex, t1, t2, baryVert, dispVert, trueVert, textureUV, lightmapUV
		local normal = baseVerts[1].normal

		local index = 0
		for v = vertStart, vertEnd - 1 do
			vertex = dispVertices[v]
			if not vertex then
			    print( "Unexpected end of vertex", "Start: " .. vertStart, "End: " .. vertEnd, "Current: " .. v )
			    break
			end

			t1 = index % ( power2 + 1 ) / power2
			t2 = math_floor( index / ( power2 + 1 ) ) / power2

			baryVert = LerpVector( t2, A + ( AD * t1 ), B + ( BC * t1 ) )
			dispVert = vertex.vec * vertex.dist
			trueVert = baryVert + dispVert
			textureUV = LerpVector( t2, uvA + ( uvAD * t1 ), uvB + ( uvBC * t1 ) )
			lightmapUV = LerpVector( t2, uv2A + ( uv2AD * t1 ), uv2B + ( uv2BC * t1 ) )

			table_insert( vertices, {
				pos = trueVert,
				normal = normal,
				u = textureUV.x,
				v = textureUV.y,
				u1 = lightmapUV.x,
				v1 = lightmapUV.y,
				userdata = { 0, 0, 0, 0 }
			} )

			index = index + 1
		end
	end

	--- Vertecies are in a grid, we need to convert them to triangles

	return vertices
end

--- Returns a table in form of a polygon-mesh. [Not Cached]
--- This will also generate displacement mesh if the face is part of a displacement.
---
--- **Note:** Displacments are "smoothed" on the GPU, and therefore the mesh between the vertices can curve.
--- @return PolygonMeshVertex[]
function meta_face:GenerateVertexData()
	--- @type PolygonMeshVertex[]
	local t = {}
	local tv = self:GetTexInfo().textureVects
	local lv = self:GetTexInfo().lightmapVecs
	local texdata = self:GetTexData()
	local mat_w, mat_h = 0, 0
	if texdata ~= nil then
		mat_w, mat_h = texdata.view_width, texdata.view_height
	end
	local n = self:GetNormal()

	-- Move the faces to match func_brushes (If any)
	local bNum = self.__bmodel
	local exPos, exAng
	if bNum > 0 then
		-- Get funch_brushes and their location
		local func_brush = __findEntityUsingBrush( self.__map )[bNum]
		if func_brush then
			exPos = func_brush.origin
			exAng = func_brush.angles
		end
	end

	local luxelW = self.LightmapTextureSizeInLuxels[1] + 1
	local luxelH = self.LightmapTextureSizeInLuxels[2] + 1

	for i = 0, self.numedges - 1 do
		--- @class PolygonMeshVertex
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

		vert.u1 = ( ( lv[0][0] * a.x + lv[0][1] * a.y + lv[0][2] * a.z + lv[0][3] ) - self.LightmapTextureMinsInLuxels[1] ) / luxelW
		vert.v1 = ( ( lv[1][0] * a.x + lv[1][1] * a.y + lv[1][2] * a.z + lv[1][3] ) - self.LightmapTextureMinsInLuxels[2] ) / luxelH

		local biangent = vert.normal:Cross(vector_up)
		vert.tangent = biangent:Cross(vert.normal):GetNormalized()
		vert.binormal = vert.normal:Cross(vert.tangent)

		vert.userdata = { vert.tangent.x, vert.tangent.y, vert.tangent.z, 0 } -- Todo: Calculate this?
		t[i + 1] = vert
	end

	if self:IsDisplacement() then
		return GetDisplacementVertexs( self, t )
	end
	return t
end

--- @return PolygonMeshVertex[]?
local function PolyChop( o_vert )
	local vert = {}
	if #o_vert < 3 then return end

	local n = 1
	local triCount = #o_vert - 2

	for i = 1, triCount do
		vert[n] 	= o_vert[1]
		vert[n + 1] = o_vert[i + 1]
		vert[n + 2] = o_vert[i + 2]
		n = n + 3
	end

	return vert
end

---Converts a grid-based mesh to triangle-mesh
---@param grid PolygonMeshVertex
---@return PolygonMeshVertex[]
local function GridPolyChop(grid)
	local width = math.sqrt(#grid)
	local height = #grid / width
    local triangles = {}

	for i = 1, height - 1 do
        for j = 1, width - 1 do
            local index1 = (i - 1) * width + j
            local index2 = i * width + j
            local index3 = i * width + j + 1

            table.insert(triangles, grid[index1])
			table.insert(triangles, grid[index2])
			table.insert(triangles, grid[index3])

            local index4 = (i - 1) * width + j + 1
            table.insert(triangles, grid[index1])
			table.insert(triangles,grid[index3])
			table.insert(triangles,grid[index4])
        end
    end

    return triangles
end


---Returns a table in form of a polygon-mesh for triangles. [Not Cached]
---@return PolygonMeshVertex[]?
function meta_face:GenerateVertexTriangleData()
	if self._vertTriangleData then return self._vertTriangleData end
	if not self:IsDisplacement() then
		self._vertTriangleData = PolyChop( self:GenerateVertexData() )
	else
		-- Displacments are build in a rows within a grid, we need to convert them to triangles
		self._vertTriangleData = GridPolyChop(self:GenerateVertexData())
	end
	return self._vertTriangleData
end

--- All mesh-data regarding said face. Should use face:GenerateVertexTriangleData intead.
--- @return PolygonMeshData
function meta_face:GenerateMeshData()
	--- @class PolygonMeshData
	local t = {}
	t.verticies = self:GenerateVertexData()
	t.triangles = PolyChop( t.verticies )
	t.material = self:GetTexture()
	return {t}
end

do
	local function calculateTriangleArea(v1, v2, v3)
		local crossProduct = (v2 - v1):Cross(v3 - v1)
		return crossProduct:Length() / 2.0
	end

	--- Returns the surface area of the face.
	--- @return number
	function meta_face:GetArea()
		if self.surfacearea then return self.surfacearea end
		self.surfacearea = 0
		local triangles = self:GenerateVertexTriangleData()
		if not triangles then return 0 end
		-- Concatenate all the vertices from the triangles into the vertices table
		for i = 1, #triangles, 3 do
			local v1, v2, v3 = triangles[i].pos, triangles[i + 1].pos, triangles[i + 2].pos
			self.surfacearea = self.surfacearea + calculateTriangleArea(v1,v2,v3)
		end
		return self.surfacearea
	end
end

if CLIENT then
	--- @type IMesh[]
	NIKNAKS_TABOMESH = NIKNAKS_TABOMESH or {}

	--- Builds the mesh if face has none.
	--- @return IMesh|boolean?
	function meta_face:BuildMesh(col)
		if SERVER then return end
		if self._mesh then return self._mesh end
		col = col or color_white
		-- Tex
		local texinfo = self:GetTexInfo()
		if texinfo ~= nil and (bit.band( texinfo.flags, 0x80 ) ~= 0 or bit.band( texinfo.flags, 0x200 ) ~= 0) then
			self._mesh = false
			return self._mesh
		end

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
			mesh.Color(col.r, col.g, col.b, col.a)
			mesh.TexCoord( 0, vert.u, vert.v ) -- Set the texture UV coordinates
			mesh.TexCoord( 1, vert.lu, vert.lv ) -- Set the lightmap UV coordinates
			mesh.TexCoord( 2, vert.lu, vert.lv  ) -- Set the lightmap UV coordinates
			--mesh.TexCoord( 2, self.LightmapTextureSizeInLuxels[1], self.LightmapTextureSizeInLuxels[2] ) -- Set the texture UV coordinates
			--mesh.TexCoord( 2, self.LightmapTextureMinsInLuxels[1], self.LightmapTextureMinsInLuxels[2] ) -- Set the texture UV coordinates
			mesh.AdvanceVertex()
		end

		mesh.End()

		table.insert( NIKNAKS_TABOMESH, self._mesh )
		return self._mesh
	end

	--- Returns the mesh generated for the face.
	--- Note. Need to call face:BuildMesh first.
	--- @return IMesh|boolean?
	function meta_face:GetMesh()
		return self._mesh
	end

	--- Deletes the mesh generated for the face.
	--- @return self
	function meta_face:DeleteMesh()
		if not self._mesh then return self end
		self._mesh:Destroy()
		self._mesh = nil
		return self
	end

	--- Generates a mesh for the face and renders it.
	function meta_face:DebugRender( iMaterial)	
		render.SetMaterial( iMaterial or  self:GetMaterial() )
		local verts = self:GenerateVertexTriangleData()
		if not verts then return end
		mesh.Begin(nil, MATERIAL_TRIANGLES, #verts / 3 ) -- Begin writing to the dynamic mesh
		for i = 1, #verts do
			mesh.Position( verts[i].pos ) -- Set the position
			mesh.TexCoord( 0, verts[i].u, verts[i].v ) -- Set the texture UV coordinates
			mesh.TexCoord( 1, verts[i].u1, verts[i].v1 ) -- Set the light UV coordinates
			mesh.AdvanceVertex() -- Write the vertex
		end
		mesh.End() -- Finish writing the mesh and draw it

		return true
	end

	for _, _mesh in pairs( NIKNAKS_TABOMESH ) do
		if IsValid( _mesh ) then _mesh:Destroy() end
	end
end
