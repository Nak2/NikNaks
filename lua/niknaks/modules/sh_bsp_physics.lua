-- Copyright © 2022-2072, Nak, https://steamcommunity.com/id/Nak2/
-- All Rights Reserved. Not allowed to be reuploaded.
-- License: https://github.com/Nak2/NikNaks/blob/main/LICENSE

--[[
	LUMP_PHYSCOLLIDE (29): records ended by modelIndex = -1. Each is
	struct dphysmodel_t
	{
		int modelIndex;   // Which brush model (index into the BModel lump, 0 = world)
		int dataSize;     // Bytes of collision data that follow
		int keydataSize;  // Bytes of key-value text that follow the collision data
		int solidCount;   // How many solids the collision data holds
	};

	followed by solidCount solids ( int size; byte data[size] ) and keydataSize bytes of key-value text.
	The solid data itself is read by sh_bsp_physmesh.lua.
]]

NikNaks.Physics = NikNaks.Physics or {}

--- @class BSPObject
local meta = NikNaks.__metatables["BSP"]

local LUMP_PHYSCOLLIDE = 29
local HEADER_BITS = 128 -- 4 ints

--- @class BSPPhysSolid
--- @field index number # 1-based index inside the model
--- @field size number # Bytes of solid data
--- @field bit number # Where the solid data starts in the lump, in BITS (use BSPObject:GetLump( 29 ):Seek( bit ) )

--- @class BSPPhysModel
--- @field modelIndex number # Brush model this belongs to. 0 is the world.
--- @field dataSize number # Bytes of collision data, as written in the header
--- @field keydataSize number # Bytes of key-value text, as written in the header
--- @field solidCount number # Solids, as written in the header
--- @field dataBit number # Where this model's collision data starts in the lump, in bits
--- @field solids BSPPhysSolid[] # The solids that were found
--- @field solidBytes number # Bytes the solids actually occupy (size headers included). Should equal dataSize
--- @field keydata string # The key-value text
--- @field blocks { name: string, keys: table<string, string> }[]? # The key-value text as  name { key value }  blocks
--- @field solidInfo table<number, { name: string, keys: table<string, string> }>? # Block of solid i ("solid", "staticsolid", "fluid"): keys.contents, keys.mass, ...
--- @field problem string? # Set if an error occured

---Returns the physics-collision records of the map, in file order. Each describes a brush model and where its solids are.
--- @return BSPPhysModel[]
function meta:GetPhysModels()
	if self._physmodels then return self._physmodels end
	self._physmodels = {}

	local header = self._lumpheader[LUMP_PHYSCOLLIDE]
	if not header or header.filelen <= 0 then return self._physmodels end

	local data = self:GetLump( LUMP_PHYSCOLLIDE )
	local total = data:Size() -- bits
	local pos = 0

	while pos + HEADER_BITS <= total do
		data:Seek( pos )
		local modelIndex = data:ReadLong()
		local dataSize = data:ReadLong()
		local keydataSize = data:ReadLong()
		local solidCount = data:ReadLong()
		pos = pos + HEADER_BITS

		if modelIndex < 0 then break end

		--- @class BSPPhysModel
		local model = {
			modelIndex = modelIndex, dataSize = dataSize, keydataSize = keydataSize, solidCount = solidCount,
			dataBit = pos, solids = {}, solidBytes = 0, keydata = "",
		}
		self._physmodels[#self._physmodels + 1] = model

		if dataSize < 0 or keydataSize < 0 or solidCount < 0 or pos + ( dataSize + keydataSize ) * 8 > total then
			model.problem = "header sizes exceed the lump"
			break
		end

		local sp = pos
		for s = 1, solidCount do
			if sp + 32 > pos + dataSize * 8 then
				model.problem = string.format( "solid %d is out of bounds", s )
				break
			end
			data:Seek( sp )
			local size = data:ReadLong()
			if size < 0 or sp + 32 + size * 8 > pos + dataSize * 8 then
				model.problem = string.format( "solid %d has a bad size (%d)", s, size )
				break
			end

			data:Seek( sp + 32 )
			model.solids[s] = { index = s, size = size, bit = sp + 32 }
			model.solidBytes = model.solidBytes + 4 + size
			sp = sp + 32 + size * 8
		end

		if not model.problem and model.solidBytes ~= dataSize then
			model.problem = string.format( "solids total %d bytes, header says %d", model.solidBytes, dataSize )
		end

		if keydataSize > 0 then
			data:Seek( pos + dataSize * 8 )
			model.keydata = data:Read( keydataSize )

			-- name { "key" "value" ... } blocks; those with an "index" (0-based) describe a solid
			model.blocks, model.solidInfo = {}, {}
			for name, body in model.keydata:gmatch( '([%w_]+)%s*(%b{})' ) do
				local keys = {}
				for k, v in body:gmatch( '"([^"]*)"%s*"([^"]*)"' ) do keys[k] = v end
				local block = { name = name, keys = keys }
				model.blocks[#model.blocks + 1] = block
				local index = tonumber( keys.index )
				if index then model.solidInfo[index + 1] = block end
			end
		end

		pos = pos + ( dataSize + keydataSize ) * 8
	end

	return self._physmodels
end

local function PhysModelFilter(m, modelIndex) return m.modelIndex == modelIndex end

---Returns the physics-collision record of a brush model (0 = world), or nil if it has none.
--- @param modelIndex number
--- @return BSPPhysModel?
function meta:GetPhysModel( modelIndex )
	return NikNaks.LINQ(self:GetPhysModels()):Where(PhysModelFilter, modelIndex):First()
end

--- @class BSPPhysDisp
--- @field index number # 0-based, in the order of the displacement list
--- @field size number # Bytes of collision data (0 = none for this displacement)
--- @field bit number # Where the data starts in the lump, in bits

---Returns the per-displacement collision blobs of LUMP_PHYSDISP (28). Layout:
---	ushort count; ushort dataSize[count]; then the blobs. Expected to be VPHY solids (see NikNaks.Physics.ParseSolid).
--- @return BSPPhysDisp[]
function meta:GetPhysDisps()
	if self._physdisps then return self._physdisps end
	self._physdisps = {}

	local header = self._lumpheader[28]
	if not header or header.filelen < 2 then return self._physdisps end

	local data = self:GetLump( 28 )
	local count = data:ReadUShort()
	local sizes = {}
	for i = 1, count do sizes[i] = data:ReadUShort() end

	local pos = ( 2 + count * 2 ) * 8
	for i = 1, count do
		local size = sizes[i]
		if pos + size * 8 > data:Size() then
			self._physdisps.problem = string.format( "blob %d is out of bounds", i )
			break
		end
		data:Seek( pos )
		self._physdisps[i] = { index = i - 1, size = size, bit = pos }
		pos = pos + size * 8
	end

	return self._physdisps
end
