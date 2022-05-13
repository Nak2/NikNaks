-- Copyright © 2022-2072, Nak, https://steamcommunity.com/id/Nak2/
-- All Rights Reserved. Not allowed to be reuploaded.

do
	local cache = {}
	---Returns the model's hull size.
	---@param name string
	---@return Vector MinVec
	---@return Vector MaxVec
	function ModelSize(name)
		if cache[name] then return cache[name][1],cache[name][2] end
		if not file.Exists(name,"GAME") then
			cache[name] = {Vector(0,0,0),Vector(0,0,0)}
			return cache[name]
		end
		local f = file.Open(name,"r", "GAME")
		f:Seek(104)
		local hullMin = Vector( f:ReadFloat(),f:ReadFloat(),f:ReadFloat())
		local hullMax = Vector( f:ReadFloat(),f:ReadFloat(),f:ReadFloat())
		f:Close()
		cache[name] = {hullMin,hullMax}
		return hullMin,hullMax
	end
end

do
	---Returns the materials used for this model. This can be exspensive, so cache the result.
	---@param name any
	---@param lod? number
	---@param bodygroupMask? number
	---@return table
	function ModelMaterials( name, lod, bodygroupMask )
		local data = util.GetModelMeshes( name, lod or 0, bodygroupMask or 0 )
		if not data then return {} end
		local t = {}
		for i = 1, #data do
			if not data[i]["material"] then continue end
			table.insert(t, ( Material ( data[i]["material"] ) ) )
		end
		return t
	end
end