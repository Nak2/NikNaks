-- Copyright © 2022-2072, Nak, https://steamcommunity.com/id/Nak2/
-- All Rights Reserved. Not allowed to be reuploaded.
local NikNaks = NikNaks
local tostring, tonumber, tobool, Angle, Vector, string_ToColor = tostring, tonumber, tobool, Angle, Vector, string.ToColor


-- Lua based type fix 
-- TODO: Note sure if it should be added
if false then
	NikNaks.oldType = type
	function NikNaks.isnumber( var )
		local mt = getmetatable( var )
		if not mt or mt.MetaName ~= "number" then return false end
		return true
	end
	function NikNaks.isstring( var )
		local mt = getmetatable( var )
		if not mt or mt.MetaName ~= "string" then return false end
		return true
	end
	function NikNaks.istable( var )
		if not getmetatable( var ) then return true end
		return false
	end
	function NikNaks.isfunction( var )
		local mt = getmetatable( var )
		if not mt or mt.MetaName ~= "function" then return false end
		return true
	end
	function NikNaks.isvector( var )
		local mt = getmetatable( var )
		if not mt or mt.MetaName ~= "Vector" then return false end
		return true
	end
	function NikNaks.isangle( var )
		local mt = getmetatable( var )
		if not mt or mt.MetaName ~= "Angle" then return false end
		return true
	end
	function NikNaks.isbool( var )
		return var == true or var == false or false
	end
	function NikNaks.isplayer( var )
		local mt = getmetatable( var )
		if not mt or mt.MetaName ~= "Player" then return false end
		return true
	end
	function NikNaks.isentity( var )
		local mt = getmetatable( var )
		if not mt or (mt.MetaName ~= "Player" and mt.MetaName ~= "Entity" ) then return false end
		return true
	end
	local function PatchMetaName( var, str )
		-- If it has a metatable.
		local mt =  getmetatable(var)
		if mt then -- Make sure the metatable has the metaname
			mt.MetaName = str
		else
			local tab = {["MetaName"] = str}
			debug.setmetatable(var, tab)
		end
	end
	PatchMetaName("", "string")
	PatchMetaName(1, "number")
	PatchMetaName(function() end, "function")
	PatchMetaName(coroutine.create(function() end), "thread")

	function NikNaks.type( var )
		local mt = getmetatable( var )
		if mt and mt.MetaName then return mt.MetaName end
		return "table"
	end
end

--- Same as AccessorFunc, but will make 'Set' functions return self. Allowing you to chain-call.
--- @param tab table
--- @param varname string
--- @param name string
--- @param iForce? number
function NikNaks.AccessorFuncEx( tab, varname, name, iForce )
	if not tab then debug.Trace() end
	tab[ "Get" .. name ] = function( self ) return self[ varname ] end
	if ( iForce == FORCE_STRING ) then
		tab[ "Set" .. name ] = function( self, v ) self[ varname ] = tostring( v ) return self end
	return end
	if ( iForce == FORCE_NUMBER ) then
		tab[ "Set" .. name ] = function( self, v ) self[ varname ] = tonumber( v ) return self end
	return end
	if ( iForce == FORCE_BOOL ) then
		tab[ "Set" .. name ] = function( self, v ) self[ varname ] = tobool( v ) return self end
	return end
	if ( iForce == FORCE_ANGLE ) then
		tab[ "Set" .. name ] = function( self, v ) self[ varname ] = Angle( v ) return self end
	return end
	if ( iForce == FORCE_COLOR ) then
		tab[ "Set" .. name ] = function( self, v )
			if ( NikNaks.type( v ) == "Vector" ) then self[ varname ] = v:ToColor()
			else self[ varname ] = string_ToColor( tostring( v ) ) end
			return self
		end
	return end
	if ( iForce == FORCE_VECTOR ) then
		tab[ "Set" .. name ] = function( self, v )
			if ( IsColor( v ) ) then self[ varname ] = v:ToVector()
			else self[ varname ] = Vector( v ) end
			return self
		end
	return end
	tab[ "Set" .. name ] = function( self, v ) self[ varname ] = v return self end
end

NikNaks.util = {}

-- Hull
do
	--- Returns a HULL_ENUM fitting the hull given.
	--- @param vecMin Vector
	--- @param vecMax Vector
	--- @return number HULL_ENUM
	function NikNaks.util.FindHull( vecMin, vecMax )
		local wide = max(-vecMin.x, -vecMin.y, vecMax.x, vecMax.y)
		local high = vecMax.z - vecMin.z
		if wide <= 16 and high <= 8 then
			return NikNaks.HULL_TINY_CENTERED
		elseif wide <= 24 and high <= 24 then
			return NikNaks.HULL_TINY
		elseif wide <= 40 and high <= 40 then
			return NikNaks.HULL_SMALL_CENTERED
		elseif wide <= 36 and high <= 65 then
			return NikNaks.HULL_MEDIUM
		elseif wide <= 32 and high <= 73 then
			return NikNaks.HULL_HUMAN
		elseif wide <= 36 and high <= 100 then
			return NikNaks.HULL_MEDIUM_TALL
		else
			return NikNaks.HULL_LARGE
		end
	end

	--- Returns a HULL_ENUM matching the entitys hull.
	--- @param entity Entity
	--- @return number HULL_ENUM
	function NikNaks.util.FindEntityHull( entity )
		if entity.GetHull then return entity:GetHull() end
		local mi, ma = entity:OBBMins(), entity:OBBMaxs()
		return FindHull( mi, ma )
	end
end
