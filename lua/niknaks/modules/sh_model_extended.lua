-- Copyright © 2022-2072, Nak, https://steamcommunity.com/id/Nak2/
-- All Rights Reserved. Not allowed to be reuploaded.
local NikNaks = NikNaks
do
	local file_Open, file_Exists = file.Open, file.Exists
	local cache = {}

	--- Returns the model's hull size.
	--- @param name string
	--- @return Vector MinVec
	--- @return Vector MaxVec
	function NikNaks.ModelSize( name )
		if cache[name] then
			return Vector( cache[name][1] ), Vector( cache[name][2] )
		end

		if not file_Exists( name, "GAME" ) then
			cache[name] = { NikNaks.vector_zero, NikNaks.vector_zero }
			return Vector( cache[name][1] ), Vector( cache[name][2] )
		end

		local f = file_Open( name, "r", "GAME" )

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
	--- @return table
	function NikNaks.ModelMaterials( name, lod, bodygroupMask )
		local data = util_GetModelMeshes( name, lod or 0, bodygroupMask or 0 )
		if not data then return {} end

		local t = {}
		for i = 1, #data do
			local mat = data[i]["material"]

			if mat then
				table.insert( t, Material( mat ) )
			end
		end

		return t
	end
end
