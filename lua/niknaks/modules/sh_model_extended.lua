-- Copyright © 2022-2072, Nak, https://steamcommunity.com/id/Nak2/
-- All Rights Reserved. Not allowed to be reuploaded.
local NikNaks = NikNaks
do
	local file_Open, file_Exists = file.Open, file.Exists
	local cache = {}

	local CACHE_CAP = 2048
	local order = {}
	local orderHead = 1
	local orderTail = 0
	local count = 0

	local function cacheSet( name, entry )
		cache[name] = entry
		orderTail = orderTail + 1
		order[orderTail] = name
		count = count + 1

		if count > CACHE_CAP then
			local oldest = order[orderHead]
			order[orderHead] = nil
			orderHead = orderHead + 1
			cache[oldest] = nil
			count = count - 1
		end
	end

	--- Returns the model's hull size. If the model is not found, it will return two zero vectors.
	--- @param name string
	--- @return Vector MinVec
	--- @return Vector MaxVec
	function NikNaks.ModelSize( name )
		if cache[name] then
			return Vector( cache[name][1] ), Vector( cache[name][2] )
		end

		if not file_Exists( name, "GAME" ) then
			cacheSet( name, { Vector(), Vector() } )
			return Vector( cache[name][1] ), Vector( cache[name][2] )
		end

		local f = file_Open( name, "rb", "GAME" )
		if f == nil then
			cacheSet( name, { Vector(), Vector() } )
			return Vector( cache[name][1] ), Vector( cache[name][2] )
		end

		f:Seek( 104 )

		local hullMin = f:ReadVector()
		local hullMax = f:ReadVector()

		f:Close()

		cacheSet( name, { hullMin, hullMax } )
		return Vector( hullMin ), Vector( hullMax )
	end
end

if CLIENT then
	local file_Open = file.Open

	-- studio.h and optimize.h describe the on-disk Source PC vertex streams.
	-- VHV color indices follow the DX90 strip groups, while GetModelMeshes
	-- can expose those vertices in a different order.
	local STUDIO_VERTEX_SIZE = 48
	local MAX_VERTICES = 20000
	local MAX_FILE_SIZE = 8 * 1024 * 1024

	local function uint( stream, offset )
		assert( offset >= 0 and offset + 4 <= #stream )
		local a, b, c, d = stream:byte( offset + 1, offset + 4 )
		return a + b * 256 + c * 65536 + d * 16777216
	end

	local function records( stream, start, count, stride )
		assert( count <= MAX_VERTICES and start >= 0 and start + count * stride <= #stream )
		local i = 0
		return function()
			if i >= count then return end
			local offset = start + i * stride
			i = i + 1
			return offset
		end
	end

	--- Returns the position and normal key used by ModelVertexLightingOrder.
	--- @param pos Vector
	--- @param normal Vector
	--- @return string
	function NikNaks.ModelVertexKey( pos, normal )
		return string.format( "%.4f %.4f %.4f %.4f %.4f %.4f", pos.x + 0, pos.y + 0, pos.z + 0,
			normal.x + 0, normal.y + 0, normal.z + 0 )
	end

	local function readVertexOrder( mdl, vvd, vtx, checksum, pause )
		assert( mdl:sub( 1, 4 ) == "IDST" and vvd:sub( 1, 4 ) == "IDSV" )
		assert( uint( mdl, 8 ) == checksum and uint( vvd, 8 ) == checksum and uint( vtx, 16 ) == checksum )
		assert( uint( vvd, 4 ) == 4 and uint( vtx, 0 ) == 7 )
		local studioVersion = uint( mdl, 4 )
		assert( studioVersion >= 44 and studioVersion <= 49 )

		local vertexCount, vertexStart = uint( vvd, 16 ), uint( vvd, 56 )
		assert( vertexCount > 0 and vertexCount <= MAX_VERTICES and vertexStart + vertexCount * STUDIO_VERTEX_SIZE <= #vvd )
		local vertexData = NikNaks.BitBuffer( vvd )
		local fixups = {}
		for fixup in records( vvd, uint( vvd, 52 ), uint( vvd, 48 ), 12 ) do
			local first, count = uint( vvd, fixup + 4 ), uint( vvd, fixup + 8 )
			assert( first + count <= vertexCount and #fixups + count <= vertexCount )
			for i = first, first + count - 1 do fixups[#fixups + 1] = i end
		end
		assert( #fixups == 0 or #fixups == vertexCount )

		local keys, groups, total = {}, {}, 0
		local bodyCount, studioBody = uint( mdl, 232 ), uint( mdl, 236 )
		assert( bodyCount > 0 and bodyCount <= 64 and bodyCount == uint( vtx, 28 ) )
		for body in records( vtx, uint( vtx, 32 ), bodyCount, 8 ) do
			local modelCount, studioModel = uint( mdl, studioBody + 4 ), studioBody + uint( mdl, studioBody + 12 )
			assert( modelCount == uint( vtx, body ) and modelCount <= 64 )
			for model in records( vtx, body + uint( vtx, body + 4 ), modelCount, 8 ) do
				assert( uint( vtx, model ) > 0 )
				local lod = model + uint( vtx, model + 4 )
				local meshCount, studioMesh = uint( mdl, studioModel + 72 ), studioModel + uint( mdl, studioModel + 76 )
				local modelBase = uint( mdl, studioModel + 84 ) / STUDIO_VERTEX_SIZE
				assert( modelBase % 1 == 0 and meshCount == uint( vtx, lod ) )
				for msh in records( vtx, lod + uint( vtx, lod + 4 ), meshCount, 9 ) do
					local meshBase = modelBase + uint( mdl, studioMesh + 12 )
					local meshCount = uint( mdl, studioMesh + 8 )
					for strip in records( vtx, msh + uint( vtx, msh + 4 ), uint( vtx, msh ), 25 ) do
						local count = uint( vtx, strip )
						assert( total + count <= MAX_VERTICES )
						total = total + count
						local group = {}
						for vertex in records( vtx, strip + uint( vtx, strip + 4 ), count, 9 ) do
							local low, high = vtx:byte( vertex + 5, vertex + 6 )
							local meshVertex = low + high * 256
							local index = meshBase + meshVertex
							assert( meshVertex < meshCount and index < vertexCount )
							if not keys[index] then
								local fileVertex = fixups[index + 1] or index
								vertexData:Seek( ( vertexStart + fileVertex * STUDIO_VERTEX_SIZE + 16 ) * 8 )
								local pos, normal = vertexData:ReadVector(), vertexData:ReadVector()
								keys[index] = NikNaks.ModelVertexKey( pos, normal )
							end
							group[#group + 1] = keys[index]
							if pause and #group % 512 == 0 then pause() end
						end
						if count > 0 then groups[#groups + 1] = group end
					end
					studioMesh = studioMesh + 116
				end
				studioModel = studioModel + 148
			end
			studioBody = studioBody + 16
		end
		return groups
	end

	local function readModelFile( path )
		local stream = file_Open( path, "rb", "GAME" )
		if not stream then return end
		local size = stream:Size()
		-- Read compressed pakfile entries sequentially. Seeking once per
		-- vertex in a ZIP-LZMA entry repeatedly decompresses the model.
		local data = size > 0 and size <= MAX_FILE_SIZE and stream:Read( size )
		stream:Close()
		return data
	end

	--- Returns the model vertex keys in the finest DX90 strip-group order.
	--- @param path string # Model path, including .mdl
	--- @param checksum number # Checksum shared by the model and baked lighting
	--- @param pause function? # Called between file reads and during larger decodes
	--- @return string[][]?
	function NikNaks.ModelVertexLightingOrder( path, checksum, pause )
		local mdl = readModelFile( path )
		if not mdl then return end

		local stem = path:sub( 1, -5 )
		if pause then pause() end
		local vvd = readModelFile( stem .. ".vvd" )
		if not vvd then return end
		if pause then pause() end
		local vtx = readModelFile( stem .. ".dx90.vtx" )
		if not vtx then return end
		local ok, order = pcall( readVertexOrder, mdl, vvd, vtx, checksum, pause )
		if ok then return order end
	end
end

do
	local util_GetModelMeshes, Material = util.GetModelMeshes, Material

	local function meshHasMaterial( v )
		return v.material ~= nil
	end

	local function meshToMaterial( v )
		return (Material( v.material ))
	end

	--- Returns the materials used for this model. This can be expensive, so cache the result.
	--- @param name any
	--- @param lod? number
	--- @param bodygroupMask? number
	--- @return IMaterial[]
	function NikNaks.ModelMaterials( name, lod, bodygroupMask )
		local data = util_GetModelMeshes( name, lod or 0, bodygroupMask or 0 )
		if not data then return {} end

		return NikNaks.LINQ( data )
			:Where( meshHasMaterial )
			:Select( meshToMaterial )
			:ToTable()
	end
end
