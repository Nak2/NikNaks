-- Copyright © 2022-2072, Nak, https://steamcommunity.com/id/Nak2/
-- All Rights Reserved. Not allowed to be reuploaded.
-- License: https://github.com/Nak2/NikNaks/blob/main/LICENSE

--[[
	VPHY solids (IVP compact surface), used by the map's physics lump and by .phy files. Offsets are in bytes, relative to their struct.
		collideheader (28):  char[4] "VPHY"; short version; short modelType (0 = compact surface); int surfaceSize; float[3] dragAxisAreas; int axisMapSize
		IVP_Compact_Surface (48):  float[3] mass_center; float[3] rotation_inertia; float upper_limit_radius; uint byte_size; int offset_ledgetree_root; int[3] dummy
		IVP_Compact_Ledgetree_Node (28):  int offset_right_node (0 = leaf, left child follows); int offset_compact_ledge; float[3] center; float radius; ...
		IVP_Compact_Ledge (16), then n_triangles triangles - one convex piece:  int c_point_offset; int client_data; uint flags/size; short n_triangles; short pad
		IVP_Compact_Triangle (16):  uint ( tri_index:12, pierce_index:12, material_index:7, is_virtual:1 ); uint[3] edges ( start_point_index:16, ... )
		IVP_Compact_Poly_Point (16):  float x, y, z, w

	IVP uses meters, y up. Source units: x = ivp.x, y = ivp.z, z = -ivp.y, divided by 0.0254.
]]

NikNaks.Physics = NikNaks.Physics or {}

local METERS_PER_INCH = 0.0254
local NODE_BITS = 28 * 8
local LEDGE_BITS = 16 * 8
local TRI_BITS = 16 * 8

--- @class PhysTriangle
--- @field [1] number # Index into mesh.points (1-based)
--- @field [2] number
--- @field [3] number
--- @field virtual boolean # Closes a convex piece, not part of the original surface
--- @field material number

--- @class PhysLedge # One convex piece
--- @field tris PhysTriangle[]

--- @class PhysMesh
--- @field modelType number
--- @field version number
--- @field massCenter Vector # Source units, as are the points
--- @field points Vector[] # 1-based
--- @field ledges PhysLedge[] # Convex pieces
--- @field triCount number
--- @field virtualCount number

local cache = {} -- path -> PhysMesh[], or { error = reason } if it failed

---Reads the collision meshes of a model from its .phy file (one per solid). Cached. Returns nil and a reason on failure.
--- @param model string # e.g. "models/props_c17/oildrum001.mdl"
--- @return PhysMesh[]?
--- @return string? error
function NikNaks.Physics.Load( model )
	local path = string.StripExtension( model ) .. ".phy"
	local known = cache[path]
	if known then
		if known.error then return nil, known.error end
		return known
	end

	local function fail( why )
		cache[path] = { error = why }
		return nil, why
	end

	if not file.Exists( path, "GAME" ) then return fail( "no .phy file" ) end
	local raw = file.Read( path, "GAME" )
	if not raw or #raw < 16 then return fail( "the .phy file is empty" ) end

	local data = NikNaks.BitBuffer( raw )
	data:Seek( 0 )
	local headerSize = data:ReadLong()
	data:Skip( 32 ) -- id
	local solidCount = data:ReadLong()
	if headerSize < 16 or headerSize > 64 or solidCount <= 0 or solidCount > 64 then
		return fail( string.format( "unexpected .phy header (size %d, %d solids)", headerSize, solidCount ) )
	end

	local meshes, firstError = {}, nil
	local pos = headerSize * 8
	for _ = 1, solidCount do
		if pos + 32 > data:Size() then break end
		data:Seek( pos )
		local size = data:ReadLong()
		if size <= 0 or pos + 32 + size * 8 > data:Size() then break end

		local mesh, err = NikNaks.Physics.ParseSolid( data, pos + 32, size )
		if mesh then meshes[#meshes + 1] = mesh else firstError = firstError or err end
		pos = pos + 32 + size * 8
	end

	if #meshes == 0 then return fail( firstError or "no readable solid" ) end
	cache[path] = meshes
	return meshes
end

---Reads one VPHY solid into a mesh. Returns nil and a reason on failure.
--- @param data BitBuffer # The BSP lump or .phy file
--- @param startBit number # Where the "VPHY" header starts, in bits
--- @param size number? # Bytes in the solid, for bounds checking
--- @return PhysMesh?
--- @return string? error
function NikNaks.Physics.ParseSolid( data, startBit, size )
	data:Seek( startBit )
	local id = data:Read( 4 )
	if id ~= "VPHY" then return nil, "not a VPHY solid (starts with " .. string.format( "%q", id ) .. ")" end

	local version = data:ReadUShort()
	local modelType = data:ReadUShort()
	local surfaceSize = data:ReadLong()
	if modelType ~= 0 then return nil, "unsupported collision model type " .. modelType end
	if size and surfaceSize + 28 > size then return nil, "surfaceSize runs past the end of the solid" end

	local surf = startBit + 28 * 8 -- Start of IVP_Compact_Surface: every offset is relative to this
	local limit = surf + surfaceSize * 8

	data:Seek( surf )
	local mcx, mcy, mcz = data:ReadFloat(), data:ReadFloat(), data:ReadFloat()
	data:Skip( 12 * 8 + 4 * 8 + 4 * 8 ) -- rotation_inertia, upper_limit_radius, byte_size
	local rootOffset = data:ReadLong()
	if rootOffset <= 0 or surf + rootOffset * 8 + NODE_BITS > limit then return nil, "ledge tree root is outside the surface" end

	--- @class PhysMesh
	local mesh = {
		version = version, modelType = modelType,
		massCenter = Vector( mcx / METERS_PER_INCH, mcz / METERS_PER_INCH, -mcy / METERS_PER_INCH ),
		points = {}, ledges = {}, triCount = 0, virtualCount = 0,
	}

	local pointIndex = {} -- bit position of a point in the file -> index in mesh.points
	local points, ledges = mesh.points, mesh.ledges
	local pointCount, ledgeCount, triTotal, virtTotal = 0, 0, 0, 0
	local ReadFloat, ReadLong, ReadULong, ReadShort, Seek, Skip = data.ReadFloat, data.ReadLong, data.ReadULong, data.ReadShort, data.Seek, data.Skip
	local floor = math.floor
	local function point( bit )
		local i = pointIndex[bit]
		if i then return i end
		Seek( data, bit )
		local x, y, z = ReadFloat( data ), ReadFloat( data ), ReadFloat( data )
		pointCount = pointCount + 1
		i = pointCount
		points[i] = Vector( x / METERS_PER_INCH, z / METERS_PER_INCH, -y / METERS_PER_INCH )
		pointIndex[bit] = i
		return i
	end

	-- Walk the ledge tree; each leaf names one ledge
	local stack, seen, visited = { surf + rootOffset * 8 }, {}, 0
	local sp = 1
	while sp > 0 do
		local nodeBit = stack[sp]
		stack[sp] = nil
		sp = sp - 1
		visited = visited + 1
		if seen[nodeBit] or visited > 4000000 then return nil, "bad ledge tree" end
		seen[nodeBit] = true
		if nodeBit < surf or nodeBit + NODE_BITS > limit then return nil, "ledge tree node is outside the surface" end

		Seek( data, nodeBit )
		local rightOffset = ReadLong( data )
		local ledgeOffset = ReadLong( data )

		if rightOffset == 0 then
			local ledgeBit = nodeBit + ledgeOffset * 8
			if ledgeBit < surf or ledgeBit + LEDGE_BITS > limit then return nil, "a ledge is outside the surface" end

			Seek( data, ledgeBit )
			local pointOffset = ReadLong( data )
			Skip( data, 64 ) -- ledgetree_node_offset / client_data, then flags and size_div_16
			local triCount = ReadShort( data )
			if triCount < 0 or ledgeBit + LEDGE_BITS + triCount * TRI_BITS > limit then return nil, "bad ledge triangle count" end
			local pointBase = ledgeBit + pointOffset * 8

			local tris = {}
			local triBit = ledgeBit + LEDGE_BITS
			for t = 1, triCount do
				Seek( data, triBit + ( t - 1 ) * TRI_BITS ) -- point() moves the cursor, so seek every time
				local w0 = ReadULong( data )
				local e1, e2, e3 = ReadULong( data ), ReadULong( data ), ReadULong( data )
				local a = point( pointBase + ( e1 % 65536 ) * 128 )
				local b = point( pointBase + ( e2 % 65536 ) * 128 )
				local c = point( pointBase + ( e3 % 65536 ) * 128 )
				local virtual = w0 >= 2147483648
				tris[t] = { a, b, c, virtual = virtual, material = floor( w0 / 16777216 ) % 128 }
				if virtual then virtTotal = virtTotal + 1 end
			end
			triTotal = triTotal + triCount
			ledgeCount = ledgeCount + 1
			ledges[ledgeCount] = { tris = tris }
		else
			stack[sp + 1] = nodeBit + rightOffset * 8
			stack[sp + 2] = nodeBit + NODE_BITS -- The left child is the node right after this one
			sp = sp + 2
		end
	end

	mesh.triCount, mesh.virtualCount = triTotal, virtTotal
	return mesh
end

---Axis-aligned bounds of a mesh, in Source units.
--- @param mesh PhysMesh
--- @return Vector mins
--- @return Vector maxs
function NikNaks.Physics.MeshBounds( mesh )
	local x0, y0, z0, x1, y1, z1 = math.huge, math.huge, math.huge, -math.huge, -math.huge, -math.huge
	local points = mesh.points
	for i = 1, #points do
		local x, y, z = points[i]:Unpack()
		if x < x0 then x0 = x end
		if x > x1 then x1 = x end
		if y < y0 then y0 = y end
		if y > y1 then y1 = y end
		if z < z0 then z0 = z end
		if z > z1 then z1 = z end
	end
	return Vector( x0, y0, z0 ), Vector( x1, y1, z1 )
end

---Converts a mesh into the format Entity:PhysicsInitMultiConvex takes.
--- @param mesh PhysMesh
--- @return Vector[][]
function NikNaks.Physics.ToMultiConvex( mesh )
	local points = mesh.points
	local out = {}
	for _, ledge in ipairs( mesh.ledges ) do
		local seen, hull, n = {}, {}, 0
		for _, tri in ipairs( ledge.tris ) do
			for k = 1, 3 do
				local index = tri[k]
				if not seen[index] then
					seen[index] = true
					n = n + 1
					hull[n] = points[index]
				end
			end
		end
		if n >= 4 then out[#out + 1] = hull end
	end
	return out
end

--- @class BSPObject
local meta = NikNaks.__metatables["BSP"]

---Reads a solid of the map's physics lump into a mesh (see NikNaks.Physics.ParseSolid).
--- @param modelIndex number # 0 = world
--- @param solidIndex number # 1-based, within the model
--- @return PhysMesh?
--- @return string? error
function meta:GetPhysSolidMesh( modelIndex, solidIndex )
	local model = self:GetPhysModel( modelIndex )
	if not model then return nil, "the map has no physics record for model " .. modelIndex end
	local solid = model.solids[solidIndex]
	if not solid then return nil, "model " .. modelIndex .. " has no solid " .. solidIndex end
	return NikNaks.Physics.ParseSolid( self:GetLump( 29 ), solid.bit, solid.size )
end
