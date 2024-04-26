-- Copyright © 2022-2072, Nak, https://steamcommunity.com/id/Nak2/
-- All Rights Reserved. Not allowed to be reuploaded.
local NikNaks = NikNaks
do
	local file_Open, file_Exists = file.Open, file.Exists
	local cache = {}

	--- Returns the model's hull size. If the model is not found, it will return two zero vectors.
	--- @param name string
	--- @return Vector MinVec
	--- @return Vector MaxVec
	function NikNaks.ModelSize( name )
		if cache[name] then
			return Vector( cache[name][1] ), Vector( cache[name][2] )
		end

		if not file_Exists( name, "GAME" ) then
			cache[name] = { Vector(), Vector() }
			return Vector( cache[name][1] ), Vector( cache[name][2] )
		end

		local f = file_Open( name, "r", "GAME" )
		if f == nil then
			cache[name] = { Vector(), Vector() }
			return Vector( cache[name][1] ), Vector( cache[name][2] )
		end

		f:Seek( 104 )

		local hullMin = Vector( f:ReadFloat(), f:ReadFloat(), f:ReadFloat() )
		local hullMax = Vector( f:ReadFloat(), f:ReadFloat(), f:ReadFloat() )

		f:Close()

		cache[name] = { hullMin, hullMax }
		return Vector( hullMin ), Vector( hullMax )
	end
end

do
	local util_GetModelMeshes, Material = util.GetModelMeshes, Material

	--- Returns the materials used for this model. This can be expensive, so cache the result.
	--- @param name any
	--- @param lod? number
	--- @param bodygroupMask? number
	--- @return IMaterial[]
	function NikNaks.ModelMaterials( name, lod, bodygroupMask )
		local data = util_GetModelMeshes( name, lod or 0, bodygroupMask or 0 )
		if not data then return {} end

		local t = {}
		for i = 1, #data do
			local mat = data[i]["material"]

			if mat then
				table.insert( t, (Material( mat )) )
			end
		end
		return t
	end
end
