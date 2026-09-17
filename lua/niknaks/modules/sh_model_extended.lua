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
