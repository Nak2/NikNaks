-- Copyright © 2022-2072, Nak, https://steamcommunity.com/id/Nak2/
-- All Rights Reserved. Not allowed to be reuploaded.
local NikNaks = NikNaks
local tostring, tonumber, tobool, Angle, Vector, string_ToColor = tostring, tonumber, tobool, Angle, Vector, string.ToColor


-- Lua based type fix
do	
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

---Same as AccessorFunc, but will make 'Set' functions return self. Allowing you to chain-call.
---@param tab table
---@param varname string
---@param name string
---@param iForce? number
function NikNaks.AccessorFuncEx( tab, varname, name, iForce )
	if ( !tab ) then debug.Trace() end
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
	---Returns a HULL_ENUM fitting the hull given.
	---@param vecMin Vector
	---@param vecMax Vector
	---@return number HULL_ENUM
	function NikNaks.util.FindHull( vecMin, vecMax )
		assert(type( vecMin ) == "Vector", "bad argument #1 to FindHull (Vector expected, got " .. type(vecMin) ..")")
		assert(type( vecMax ) == "Vector", "bad argument #2 to FindHull (Vector expected, got " .. type(vecMax) ..")")
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

	---Returns a HULL_ENUM matching the entitys hull.
	---@param ent Entity
	---@return number HULL_ENUM
	function NikNaks.util.FindEntityHull( entity )
		if entity.GetHull then return entity:GetHull() end
		local mi, ma = entity:OBBMins(), entity:OBBMaxs()
		return FindHull(mi, ma)
	end
end

-- A safer PrintTable, with a few more features.
do
	local getinfo = debug.getinfo
	local getlocal = debug.getlocal
	local function getfuncName( info )
		if not info.what == "C" then return end
		if not info.short_src or not info.linedefined or not file.Exists(info.short_src,"GAME") then return end
		local fil = file.Open( info.short_src, "r", "GAME" )
		if not fil then return end
		-- Goto line defined
		for i = 1, info.linedefined - 1 do
			fil:ReadLine()
		end
		local line = fil:ReadLine()
		fil:Close()
		local func = string.match( line, "([^s]+)%s-=%s-function%s-%(")
		if func then
			return string.Trim( func )
		end
		local func = string.match( line, "function%s(.-)%(")
		if func then
			return string.Trim( func )
		end
	end
	local function getFuncArgs( func )
		local args = {}
		local arg = getlocal( func, 1 )
		local i = 1
		while arg ~= nil do
			table.insert(args,arg)
			i = i + 1
			arg = getlocal( func, i )
		end
		return "(" .. table.concat( args, "," ) .. ")"
	end
	local function MsgColor( col )
		MsgC(REALM_COLOR,"Color("  .. col.r .. ", " .. col.g .. ", " .. col.b  .. (col.a ~= 255 and "," .. col.a or "") .. ")",col," ▉▉▉")
	end
	local funcCache = {}
	local function MSgFunc( func )
		local funcName = funcCache[ func ]
		local info = getinfo( func )
		if not funcName then
			funcName = getfuncName( info ) or tostring( func )
			funcCache[ func ] = funcName
		end
		local line = info.linedefined .. ":" .. info.short_src
		Msg( funcName .. getFuncArgs( func ) .. "\t\t" .. line )
	end

	function NikNaks.PrintTable( t, shorten, hide, indent, done )
		local Msg = Msg
		if shorten == nil then shorten = true end
		if hide == nil then hide = true end
	
		done = done or {}
		indent = indent or 0
		local keys = table.GetKeys( t )
	
		table.sort( keys, function( a, b )
			if ( NikNaks.isnumber( a ) && NikNaks.isnumber( b ) ) then return a < b end
			return tostring( a ) < tostring( b )
		end )
	
		done[ t ] = true
		if t.MetaName then
			done[ t.MetaName ] = true
		end

		local _shorten = false
		
		for i = 1, #keys do
			local key =  keys[ i ]
			if shorten and NikNaks.isnumber(key) and key > 15 then
				-- Check to see if we can shorten the numbers
				if not _shorten then
					local a = false
					for c = 1, 8 do
						local _next = keys[ i + c ]
						if not _next or not NikNaks.isnumber( _next ) or _next - c ~= key then
							a = true
							break
						end
					end
					_shorten = not a
				end
				if _shorten then
					local _next = keys[ i + 1 ]
					if NikNaks.isnumber( _next ) and _next == key + 1 then
						continue
					else
						Msg( string.rep( "\t", indent ), "...\n" )
						_shorten = false
					end
				end
			elseif hide and NikNaks.isstring(key) then
				if key:sub(0,1) == "_" then continue end
			end
			
			local value = t[ key ]
			Msg( string.rep( "\t", indent ) )
	
			if  ( istable( value ) and !done[ value ] and !(value.MetaName and done[ value.MetaName ]) ) then
				if value.r and value.g and value.b then
					Msg( key, "\t=\t" )
					MsgColor( value )
					MsgN()
				else
					done[ value ] = true
					Msg( key, ":", value.MetaName and "\t"..tostring(value) .."\t" .. "[" .. value.MetaName .. "]\n" or "\n")
					NikNaks.PrintTable ( value, shorten, hide, indent + 2, done )
				end
			else
				if isfunction( value ) then
					Msg( key, "\t=\t" )
					MSgFunc( value )
					MsgN()
				else
					if istable(value) and value.MetaName then
						value = tostring(value) .. "\t[" .. value.MetaName .. "]"
					end
					Msg( key, "\t=\t", value, "\n" )
				end
			end
		end
	end
end
