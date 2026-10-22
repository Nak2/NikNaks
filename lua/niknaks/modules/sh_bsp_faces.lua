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

--- Parses a Color object and exponent from the given BitBuffer
--- @param data BitBuffer
--- @return Color
--- @return number exponent
local function __readColorRGBExp32 ( data )
	local sample = {
		r = data:ReadByte(),
		g = data:ReadByte(),
		b = data:ReadByte(),
		exponent = data:ReadSignedByte()
	}
	return NikNaks.ColorRGBExp32ToColor( sample ), sample.exponent
end

local LUMP_FACES_HDR = 58
local LUMP_LIGHTING_HDR = 53

--- @class BSPFaceLightingHDR
--- @field lightofs number # Byte offset into the HDR lighting lump (53). -1 if the face has no lightmap.
--- @field styles number[] # The 4 light styles of the face (255 = unused)

--- Returns where each face's HDR lightmap is stored, from the HDR face lump (58).
--- The HDR faces have their own `lightofs` and `styles`, since the HDR lighting is compiled separately.
--- Same order as BSPObject:GetFaces() (0-based). Empty if the map has no HDR lighting.
--- @return table<number, BSPFaceLightingHDR>
function meta:GetFacesHDRLighting()
	if self._facesHDRLight then return self._facesHDRLight end

	local out = {}
	self._facesHDRLight = out

	local header = self._lumpheader[LUMP_FACES_HDR]
	if not header or header.filelen <= 0 then return out end

	-- Same 56 byte layout as GetFaces(). styles start at bit 128, lightofs follows them.
	local data = self:GetLump( LUMP_FACES_HDR )
	for i = 0, math.min( data:Size() / 448, MAX_MAP_FACES ) - 1 do
		data:Seek( i * 448 + 128 )
		local s1, s2, s3, s4 = data:ReadByte(), data:ReadByte(), data:ReadByte(), data:ReadByte()
		out[i] = { styles = { s1, s2, s3, s4 }, lightofs = data:ReadLong() }
	end

	self:ClearLump( LUMP_FACES_HDR )
	return out
end

--- Returns the lightmap samples for the face.
--- @param hdr boolean? # If true, reads the HDR lightmap (lumps 58 and 53) instead of the LDR one (lumps 7 and 8). Returns nil if the map has no HDR lighting.
--- @return table<string, LightmapSample[]>?
function meta_face:GetLightmapSamples( hdr )
	local lightofs, styles, lumpId, cacheKey

	if hdr then
		local record = self.__map:GetFacesHDRLighting()[self.__id]
		local header = self.__map._lumpheader[LUMP_LIGHTING_HDR]
		if not record or not header or header.filelen <= 0 then return end
		lightofs, styles, lumpId, cacheKey = record.lightofs, record.styles, LUMP_LIGHTING_HDR, "_lightmap_samples_hdr"
	else
		lightofs, styles, lumpId, cacheKey = self.lightofs, self.styles, 8, "_lightmap_samples"
	end

	if lightofs == -1 then return end
	if self[cacheKey] then return self[cacheKey] end

	--- @class LightmapSample
	--- @field color Color
	--- @field exponent number

	--- @type LightmapSample[]
	local full = {}

	--- @type LightmapSample[]
	local average = {}

	local samples = { average = average, full = full }
	self[cacheKey] = samples

	local mat = self:GetMaterial()
	local has_bumpmap = mat:GetString( "$bumpmap" ) ~= nil
	local luxel_count = ( self.LightmapTextureSizeInLuxels[1] + 1 ) * ( self.LightmapTextureSizeInLuxels[2] + 1 )

	local lightstyle_count = 0
	for _, v in ipairs( styles ) do
		if v ~= 255 then lightstyle_count = lightstyle_count + 1 end
	end

	-- "For faces with bumpmapped textures, there are four times the usual number of lightmap samples"
	local sample_count = lightstyle_count * luxel_count
	if has_bumpmap then sample_count = sample_count * 4 end

	local data = self.__map:GetLump( lumpId )

	-- Get the average samples
	-- "Immediately preceeding the lightofs-referenced sample group,
	--  there are single samples containing the average lighting on the face, one for each lightstyle,
	--  in reverse order from that given in the styles[] array."
	local color, exponent
	data:Seek( ( lightofs * 8 ) - ( 32 * lightstyle_count ) )
	for i = 1, lightstyle_count do
		color, exponent = __readColorRGBExp32( data )
		average[i] = { color = color, exponent = exponent }
	end
	-- BSP stores averages in reverse style order; reverse the array in-place.
	local lo, hi = 1, lightstyle_count
	while lo < hi do
		average[lo], average[hi] = average[hi], average[lo]
		lo = lo + 1;  hi = hi - 1
	end

	-- Get the full samples
	for _ = 1, sample_count do
		color, exponent = __readColorRGBExp32( data )
		table.insert( full, { color = color, exponent = exponent } )
	end

	return samples
end

do
	local floor, min, max = math.floor, math.min, math.max

	---Bilinear sample of a luxel grid. The grid is row-major, 1-based, and w x h luxels big.
	---@return number? r
	---@return number? g
	---@return number? b
	local function sampleGrid( full, w, h, u, v )
		-- u / v = s / gridSize, with s already in luxel units: sample 0 is at s = 0 (no half-luxel shift).
		local fx = max( 0, min( u * w, w - 1 ) )
		local fy = max( 0, min( v * h, h - 1 ) )
		local x0, y0 = floor( fx ), floor( fy )
		local x1, y1 = min( x0 + 1, w - 1 ), min( y0 + 1, h - 1 )
		local tx, ty = fx - x0, fy - y0

		local a, b = full[y0 * w + x0 + 1], full[y0 * w + x1 + 1]
		local c, d = full[y1 * w + x0 + 1], full[y1 * w + x1 + 1]
		if not ( a and b and c and d ) then return end
		a, b, c, d = a.color, b.color, c.color, d.color

		-- The colors are vertex-light colors where 0.5 means "1x". The engine doubles them (2x overbright), so we do too.
		-- Anything brighter than 1x is clamped to 255.
		local r1, g1, b1 = a.r + ( b.r - a.r ) * tx, a.g + ( b.g - a.g ) * tx, a.b + ( b.b - a.b ) * tx
		local r2, g2, b2 = c.r + ( d.r - c.r ) * tx, c.g + ( d.g - c.g ) * tx, c.b + ( d.b - c.b ) * tx
		return min( ( r1 + ( r2 - r1 ) * ty ) * 2, 255 ),
			min( ( g1 + ( g2 - g1 ) * ty ) * 2, 255 ),
			min( ( b1 + ( b2 - b1 ) * ty ) * 2, 255 )
	end

	---Returns the baked light color at a lightmap UV on the face (bilinear), as r, g, b in 0-255.
	---Returns nil if the face has no lightmap, or the map has no HDR lighting and hdr is true.
	--- @param u1 number # Lightmap U, as in the u1 of GenerateVertexData()
	--- @param v1 number # Lightmap V, as in the v1 of GenerateVertexData()
	--- @param hdr boolean? # Use the HDR lightmap
	--- @return number? r
	--- @return number? g
	--- @return number? b
	function meta_face:SampleLightmap( u1, v1, hdr )
		local samples = self:GetLightmapSamples( hdr )
		if not samples or #samples.full == 0 then return end
		return sampleGrid( samples.full, self.LightmapTextureSizeInLuxels[1] + 1, self.LightmapTextureSizeInLuxels[2] + 1, u1, v1 )
	end

	---Returns a baked light color for each vertex, in the same order as the vertices given. [Not Cached]
	---Each color is a table { r, g, b } in 0-255 (see BSPFaceObject:SampleLightmap for what the numbers mean).
	---Vertices outside the sampled grid get white. Returns nil if the face has no lightmap, or hdr is true and the map has no HDR lighting.
	--- @param verts PolygonMeshVertex[]? # Defaults to face:GenerateVertexTriangleData()
	--- @param hdr boolean? # Use the HDR lightmap
	--- @return { r: number, g: number, b: number }[]?
	function meta_face:GenerateLightColors( verts, hdr )
		-- GetLightmapSamples keeps every luxel on the face (two tables per luxel). Since this function isn't cached,
		-- don't leave that behind unless it was already there: it adds up to hundreds of MB on a big map.
		local cacheKey = hdr and "_lightmap_samples_hdr" or "_lightmap_samples"
		local wasCached = self[cacheKey] ~= nil

		local samples = self:GetLightmapSamples( hdr )
		if not samples then return end
		local full = samples.full

		local colors
		verts = verts or self:GenerateVertexTriangleData()
		if verts and #full > 0 then
			local w, h = self.LightmapTextureSizeInLuxels[1] + 1, self.LightmapTextureSizeInLuxels[2] + 1
			colors = {}
			for i = 1, #verts do
				local vert = verts[i]
				local r, g, b = sampleGrid( full, w, h, vert.u1, vert.v1 )
				colors[i] = { r = r or 255, g = g or 255, b = b or 255 }
			end
		end

		if not wasCached then self[cacheKey] = nil end
		return colors
	end
end

---Frees the geometry cached on the face by GenerateVertexTriangleData() and GetVertexs(). It is generated again when needed.
---Useful after building something from a lot of faces, since the cache is several tables per vertex.
function meta_face:ClearMeshData()
	self._vertTriangleData = nil
	self._vertex = nil
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
	local texinfo = self:GetTexInfo()
	if not texinfo then return nil end
	return self.__map:GetTexData()[ texinfo.texdata ]
end

--- Returns the texture for the face.
--- @return string?
function meta_face:GetTexture()
	local texdata = self:GetTexData()
	if not texdata then return nil end
	return texdata.nameStringTableID
end

--- Returns the material the face use. Note: Materials within the BSP won't be loaded.
--- @return IMaterial
function meta_face:GetMaterial()
	if self._mat then return self._mat end
	self._mat = Material( self:GetTexture() or "__error" )
	return self._mat
end

--- Returns true if the face uses the Lightmapped_4WayBlend shader.
--- @return boolean
function meta_face:IsLightmapped4WayBlend()
	if self._is4wayblend ~= nil then return self._is4wayblend end
	-- GetShader() gives the implementation name, with the DirectX version: "Lightmapped_4WayBlend_DX9" and the like
	self._is4wayblend = string.gsub( self:GetMaterial():GetShader(), "_DX%d+$", "" ) == "Lightmapped_4WayBlend"
	return self._is4wayblend
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
	local texinfo = self:GetTexInfo()
	if not texinfo then return false end
	return bit.band( texinfo.flags, 0x10 ) ~= 0
end

--- Returns true if the face is part of 2D skybox.
--- @return boolean
function meta_face:IsSkyBox()
	local texinfo = self:GetTexInfo()
	if not texinfo then return false end
	return bit.band( texinfo.flags, 0x2 ) ~= 0
end

--- Returns true if the face is part of 3D skybox.
--- @return boolean
function meta_face:IsSkyBox3D()
	local texinfo = self:GetTexInfo()
	if not texinfo then return false end
	return bit.band( texinfo.flags, 0x4 ) ~= 0
end

--- Returns true if the face's texinfo has said flag.
--- @return boolean
function meta_face:HasTexInfoFlag( flag )
	local texinfo = self:GetTexInfo()
	if not texinfo then return false end
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
---@return DispInfo?
function meta_face:GetDisplacementInfo()
	-- The face's own dispinfo index is the source of truth. The dispinfo's MapFace (which points back at the face)
	-- is only used if that index doesn't lead anywhere.
	local list, byFace = self.__map:GetDispInfo()
	return list[self.dispinfo] or byFace[self.__id]
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

	if (dot1 > 0) ~= (dot2 > 0) then
		local t = dot1 / ( dot1 - dot2 )

		if t <= 0 or t >= 1 then return end
		local poly = self:GetVertexs()
		if not poly then return end
		local dir = (endPos - startPos):GetNormalized()
		for i = 1, #poly - 2 do
            local v0 = poly[1]
            local v1 = poly[i + 1]
            local v2 = poly[i + 2]

            -- Check if ray is intersecting triangle point v0, v1 and v2
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
--- @field color Color
--- @field u number
--- @field v number
--- @field lu number
--- @field lv number
--- @field tangent Vector
--- @field binormal Vector
--- @field userdata table<number, number>

--- Shared white Colors keyed by alpha, used for displacement vertices.
--- @type table<number, Color>
local alphaColors = {}

--- @return PolygonMeshVertex[]
local function GetDisplacementVertexs(self, faceVertexData )
	local dispInfo = self:GetDisplacementInfo()
	local start = dispInfo.startPosition

	local baseVerts = faceVertexData
	assert( #baseVerts == 4 )

	local baseQuad = {}
	local startIdx = 1
	do
		local minDist = math.huge

		local pos, dist
		for i = 1, 4 do
			pos = baseVerts[i].pos
			table.insert( baseQuad, pos )

			dist = pos:Distance( start )
			if dist < minDist then
				minDist = dist
				startIdx = i
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
	local Ax, Ay, Az = A:Unpack()
	local Bx, By, Bz = B:Unpack()
	local ADx, ADy, ADz = ( D - A ):Unpack()
	local BCx, BCy, BCz = ( C - B ):Unpack()

	-- Texture and lightmap UVs are interpolated exactly like the positions (A->D along one edge,
	-- B->C along the other, then between the two), but as plain numbers: no Vector allocations per vertex.
	local quad = rotated( baseVerts )
	local q1, q2, q3, q4 = quad[1], quad[2], quad[3], quad[4]
	local uA, vA, uB, vB = q1.u, q1.v, q2.u, q2.v
	local uAD, vAD = q4.u - uA, q4.v - vA
	local uBC, vBC = q3.u - uB, q3.v - vB
	-- The lightmap of a displacement is not projected onto it like a flat face's: it is a grid with a luxel for
	-- every vertex (2^power + 1 on each side), in the same order as the vertices. So the lightmap coordinates
	-- come from the position in the grid, not from the corners of the flat face.
	local lightW, lightH = self.LightmapTextureSizeInLuxels[1] + 1, self.LightmapTextureSizeInLuxels[2] + 1
	local lightU, lightV = ( lightW - 1 ) / lightW, ( lightH - 1 ) / lightH

	local power = dispInfo.power
	local power2 = 2 ^ power
	local vertCount = ( ( 2 ^ power ) + 1 ) ^ 2
	local vertStart = dispInfo.DispVertStart
	local vertEnd = vertStart + vertCount

	local vertices = {}
	local px, py, pz = {}, {}, {} -- Final positions as numbers, used by the normal pass below
	do
		local math_floor = math.floor
		local math_Clamp = math.Clamp

		local dispVertices = self.__map:GetDispVerts()
		local dispMultiBlend = self.__map:GetDispMultiBlend()
		local isMultiBlend = self:IsLightmapped4WayBlend()
		local normal = baseVerts[1].normal

		local tangent = normal:Cross( vector_up ):Cross( normal ):GetNormalized()
		local tangentUD = { tangent.x, tangent.y, tangent.z, 1 }

		local stride = power2 + 1
		local index = 0
		for v = vertStart, vertEnd - 1 do
			local vertex = dispVertices[v]
			if not vertex then
			    print( "Unexpected end of vertex", "Start: " .. vertStart, "End: " .. vertEnd, "Current: " .. v )
			    break
			end

			local t1 = index % stride / power2
			local t2 = math_floor( index / stride ) / power2

			-- Position: lerp along both edges (t1), between the edges (t2), then add the displacement.
			local p0x, p0y, p0z = Ax + ADx * t1, Ay + ADy * t1, Az + ADz * t1
			local p1x, p1y, p1z = Bx + BCx * t1, By + BCy * t1, Bz + BCz * t1
			local dx, dy, dz = vertex.vec:Unpack()
			local dist = vertex.dist
			local x = p0x + ( p1x - p0x ) * t2 + dx * dist
			local y = p0y + ( p1y - p0y ) * t2 + dy * dist
			local z = p0z + ( p1z - p0z ) * t2 + dz * dist

			local tu0, tv0 = uA + uAD * t1, vA + vAD * t1
			local tu1, tv1 = uB + uBC * t1, vB + vBC * t1

			-- For Lightmapped_4WayBlend, pass lump-63 weights as vertex RGBA:
			--   A = blend[1] (layer 1→2),  R = blend[2] (layer 3),  G = blend[3] (layer 4),  B = blend[4] (unused).
			-- Falls back to standard displacement alpha when lump 63 is absent.
			local color
			local mb = isMultiBlend and dispMultiBlend[v]
			if mb then
				local blend = mb.multiblend
				color = Color(
					math_Clamp( blend[2] * 255, 0, 255 ),
					math_Clamp( blend[3] * 255, 0, 255 ),
					math_Clamp( blend[4] * 255, 0, 255 ),
					math_Clamp( blend[1] * 255, 0, 255 )
				)
			else
				-- Shared per alpha value: displacements have thousands of vertices but only a few distinct alphas.
				local alpha = vertex.alpha
				if alpha ~= alpha then alpha = 0 end -- NaN (a broken vertex in the lump): can't be a table key
				color = alphaColors[alpha]
				if not color then
					color = Color( 255, 255, 255, alpha )
					alphaColors[alpha] = color
				end
			end

			index = index + 1
			px[index], py[index], pz[index] = x, y, z
			vertices[index] = {
				pos = Vector( x, y, z ),
				normal = normal,
				u = tu0 + ( tu1 - tu0 ) * t2,
				v = tv0 + ( tv1 - tv0 ) * t2,
				-- t1 / t2 run 0 to 1 over the grid: luxel x = t1 * ( width - 1 ), luxel y = t2 * ( height - 1 )
				u1 = t1 * lightU,
				v1 = t2 * lightV,
				userdata = tangentUD,
				color = color,
			}
		end
	end

	-- Smooth normals: accumulate each quad's triangle normals onto its corners (plain numbers, no Vectors).
	do
		local count = #vertices
		local ax, ay, az = {}, {}, {}
		for k = 1, count do ax[k], ay[k], az[k] = 0, 0, 0 end

		local gridSize = power2 + 1
		local bnx, bny, bnz = baseVerts[1].normal:Unpack()

		for row = 0, power2 - 1 do
			for col = 0, power2 - 1 do
				local i1 = row * gridSize + col + 1
				local i2 = ( row + 1 ) * gridSize + col + 1
				local i3 = ( row + 1 ) * gridSize + col + 2
				local i4 = row * gridSize + col + 2
				local x1, y1, z1 = px[i1], py[i1], pz[i1]
				local x2, y2, z2 = px[i2], py[i2], pz[i2]
				local x3, y3, z3 = px[i3], py[i3], pz[i3]
				local x4, y4, z4 = px[i4], py[i4], pz[i4]

				if ( row + col ) % 2 == 0 then
					-- na = ( p2 - p1 ) x ( p3 - p1 ),  nb = ( p3 - p1 ) x ( p4 - p1 )
					local ux, uy, uz = x2 - x1, y2 - y1, z2 - z1
					local wx, wy, wz = x3 - x1, y3 - y1, z3 - z1
					local sx, sy, sz = x4 - x1, y4 - y1, z4 - z1
					local nax, nay, naz = uy * wz - uz * wy, uz * wx - ux * wz, ux * wy - uy * wx
					local nbx, nby, nbz = wy * sz - wz * sy, wz * sx - wx * sz, wx * sy - wy * sx
					ax[i1], ay[i1], az[i1] = ax[i1] + nax + nbx, ay[i1] + nay + nby, az[i1] + naz + nbz
					ax[i2], ay[i2], az[i2] = ax[i2] + nax,       ay[i2] + nay,       az[i2] + naz
					ax[i3], ay[i3], az[i3] = ax[i3] + nax + nbx, ay[i3] + nay + nby, az[i3] + naz + nbz
					ax[i4], ay[i4], az[i4] = ax[i4] + nbx,       ay[i4] + nby,       az[i4] + nbz
				else
					-- na = ( p2 - p1 ) x ( p4 - p1 ),  nb = ( p3 - p2 ) x ( p4 - p2 )
					local ux, uy, uz = x2 - x1, y2 - y1, z2 - z1
					local wx, wy, wz = x4 - x1, y4 - y1, z4 - z1
					local sx, sy, sz = x3 - x2, y3 - y2, z3 - z2
					local rx, ry, rz = x4 - x2, y4 - y2, z4 - z2
					local nax, nay, naz = uy * wz - uz * wy, uz * wx - ux * wz, ux * wy - uy * wx
					local nbx, nby, nbz = sy * rz - sz * ry, sz * rx - sx * rz, sx * ry - sy * rx
					ax[i1], ay[i1], az[i1] = ax[i1] + nax,       ay[i1] + nay,       az[i1] + naz
					ax[i2], ay[i2], az[i2] = ax[i2] + nax + nbx, ay[i2] + nay + nby, az[i2] + naz + nbz
					ax[i3], ay[i3], az[i3] = ax[i3] + nbx,       ay[i3] + nby,       az[i3] + nbz
					ax[i4], ay[i4], az[i4] = ax[i4] + nax + nbx, ay[i4] + nay + nby, az[i4] + naz + nbz
				end
			end
		end

		local sqrt = math.sqrt
		for k = 1, count do
			local nx, ny, nz = ax[k], ay[k], az[k]
			local lenSqr = nx * nx + ny * ny + nz * nz
			if lenSqr > 0 then
				local inv = 1 / sqrt( lenSqr )
				nx, ny, nz = nx * inv, ny * inv, nz * inv
				-- Ensure the computed normal faces the same side as the base face.
				if nx * bnx + ny * bny + nz * bnz < 0 then nx, ny, nz = -nx, -ny, -nz end
				vertices[k].normal = Vector( nx, ny, nz )
			end
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
	local texinfo = self:GetTexInfo()
	if not texinfo then return t end
	local tv = texinfo.textureVects
	local lv = texinfo.lightmapVecs
	local texdata = self:GetTexData()
	local mat_w, mat_h = 0, 0
	if texdata ~= nil then
		mat_w, mat_h = texdata.view_width, texdata.view_height
	end
	local n = self:GetNormal()

	-- Cache UV transform rows as flat locals — avoids nested table lookups per vertex.
	local tv00, tv01, tv02, tv03 = tv[0][0], tv[0][1], tv[0][2], tv[0][3]
	local tv10, tv11, tv12, tv13 = tv[1][0], tv[1][1], tv[1][2], tv[1][3]
	local lv00, lv01, lv02, lv03 = lv[0][0], lv[0][1], lv[0][2], lv[0][3]
	local lv10, lv11, lv12, lv13 = lv[1][0], lv[1][1], lv[1][2], lv[1][3]
	local lm1 = self.LightmapTextureMinsInLuxels[1]
	local lm2 = self.LightmapTextureMinsInLuxels[2]

	-- Tangent/binormal are constant for the face (normal is uniform).
	-- tangent = normalize( ( n x up ) x n ), written out for up = (0, 0, 1) with plain numbers.
	-- Same result as the Vector version, without three temporary Vectors per face.
	local nx, ny, nz = n:Unpack()
	local tx, ty, tz = -nx * nz, -ny * nz, nx * nx + ny * ny
	local tlen = ( tx * tx + ty * ty + tz * tz ) ^ 0.5
	if tlen > 0 then tx, ty, tz = tx / tlen, ty / tlen, tz / tlen end
	local tangent  = Vector( tx, ty, tz )
	local binormal = Vector( ny * tz - nz * ty, nz * tx - nx * tz, nx * ty - ny * tx ) -- n x tangent
	local tangentUD = { tx, ty, tz, 0 }

	-- Move the faces to match func_brushes (If any)
	local bNum = self.__bmodel
	local exPos, exAng
	local zeroAngle -- Only needed for faces on a brush entity
	if bNum > 0 then
		-- Get funch_brushes and their location
		local func_brush = __findEntityUsingBrush( self.__map )[bNum]
		if func_brush then
			exPos = func_brush.origin
			exAng = func_brush.angles
			zeroAngle = Angle( 0, 0, 0 )
		end
	end

	local luxelW = self.LightmapTextureSizeInLuxels[1] + 1
	local luxelH = self.LightmapTextureSizeInLuxels[2] + 1

	-- Same lookup as BSPObject:GetSurfEdgesIndex, done once per face instead of once per vertex.
	local map = self.__map
	local surfEdges, edges = map:GetSurfEdges(), map:GetEdges()
	local firstedge = self.firstedge
	local abs = math.abs

	for i = 0, self.numedges - 1 do
		local surf = surfEdges[firstedge + i]
		local edge = edges[abs( surf )]
		local a = surf >= 0 and edge[1] or edge[2]
		local pos = a
		if exAng and exPos then -- WorldPos -> Entity Brush
			pos = ( LocalToWorld( a, zeroAngle, exPos, exAng ) )
		end
		local ax, ay, az = a:Unpack()
		-- Built in one go: filling an empty table field by field makes it resize several times.
		--- @class PolygonMeshVertex
		t[i + 1] = {
			pos       = pos,
			normal    = n,
			tangent   = tangent,
			binormal  = binormal,
			-- UV & LV
			u         = ( tv00 * ax + tv01 * ay + tv02 * az + tv03 ) / mat_w,
			v         = ( tv10 * ax + tv11 * ay + tv12 * az + tv13 ) / mat_h,
			u1        = ( lv00 * ax + lv01 * ay + lv02 * az + lv03 - lm1 ) / luxelW,
			v1        = ( lv10 * ax + lv11 * ay + lv12 * az + lv13 - lm2 ) / luxelH,
			userdata  = tangentUD,
		}
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
	local width  = math.sqrt( #grid )
	local height = #grid / width
	local triangles = {}
	local n = 0

	for i = 1, height - 1 do
		for j = 1, width - 1 do
			local i1 = ( i - 1 ) * width + j
			local i2 = i * width + j
			local i3 = i * width + j + 1
			local i4 = ( i - 1 ) * width + j + 1
			if ( i + j ) % 2 == 0 then
				n = n + 1; triangles[n] = grid[i1]
				n = n + 1; triangles[n] = grid[i2]
				n = n + 1; triangles[n] = grid[i3]
				n = n + 1; triangles[n] = grid[i1]
				n = n + 1; triangles[n] = grid[i3]
				n = n + 1; triangles[n] = grid[i4]
			else
				n = n + 1; triangles[n] = grid[i1]
				n = n + 1; triangles[n] = grid[i2]
				n = n + 1; triangles[n] = grid[i4]
				n = n + 1; triangles[n] = grid[i2]
				n = n + 1; triangles[n] = grid[i3]
				n = n + 1; triangles[n] = grid[i4]
			end
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
	t.vertices = self:GenerateVertexData()
	t.triangles = self:IsDisplacement() and GridPolyChop( t.vertices ) or PolyChop( t.vertices )
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

		local verts = self:GenerateVertexTriangleData()
		if not verts then return self._mesh end

		self._mesh = Mesh( self:GetMaterial() )

		-- Vert
		local vertCount = #verts
		local cr, cg, cb, ca = col.r, col.g, col.b, col.a
		-- Lightmapped_4WayBlend reads per-vertex RGBA blend weights; use them instead of the
		-- uniform tint colour. Other surfaces keep the standard col behaviour.
		local use_vertex_color = self:IsDisplacement() and self:IsLightmapped4WayBlend()
		mesh.Begin( self._mesh, MATERIAL_TRIANGLES, vertCount / 3 )
		for i = 1, vertCount do
			local vert = verts[i]
			-- > Mesh
			mesh.Normal( vert.normal )
			mesh.Position( vert.pos )
			if use_vertex_color and vert.color then
				local vc = vert.color
				mesh.Color( vc.r, vc.g, vc.b, vc.a )
			else
				mesh.Color( cr, cg, cb, ca )
			end
			mesh.TexCoord( 0, vert.u, vert.v )   -- texture UV
			mesh.TexCoord( 1, vert.u1, vert.v1 ) -- lightmap UV
			mesh.TexCoord( 2, vert.u1, vert.v1 )
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
	function meta_face:DebugRender( iMaterial )
		render.SetMaterial( iMaterial or  self:GetMaterial() )
		local verts = self:GenerateVertexTriangleData()
		if not verts then return end
		---@diagnostic disable-next-line
		mesh.Begin( MATERIAL_TRIANGLES, #verts / 3 ) -- Begin writing to the dynamic mesh
		for i = 1, #verts do
			local vert = verts[i]
			mesh.Normal( vert.normal )
			mesh.Position( vert.pos ) -- Set the position
			mesh.Color( 255, 255, 255, 255 )
			mesh.TexCoord( 0, vert.u, vert.v ) -- Set the texture UV coordinates
			mesh.TexCoord( 1, vert.u1, vert.v1 ) -- Set the lightmap UV coordinates
			mesh.TexCoord( 2, vert.u1, vert.v1 ) -- Set the lightmap UV coordinates
			mesh.TangentS( 0, 0, 0 )
			mesh.TangentT( 0, 0, 0 )
			mesh.AdvanceVertex() -- Write the vertex
		end
		mesh.End() -- Finish writing the mesh and draw it

		return true
	end

	for _, _mesh in pairs( NIKNAKS_TABOMESH ) do
		if IsValid( _mesh ) then _mesh:Destroy() end
	end
end
