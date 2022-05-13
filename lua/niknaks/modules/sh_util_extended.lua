-- Copyright © 2022-2072, Nak, https://steamcommunity.com/id/Nak2/
-- All Rights Reserved. Not allowed to be reuploaded.

---Same as AccessorFunc, but will make 'Set' functions return self. Allowing you to chain-call.
---@param tab table
---@param varname string
---@param name string
---@param iForce? number
function AccessorFuncEx( tab, varname, name, iForce )
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
			if ( type( v ) == "Vector" ) then self[ varname ] = v:ToColor()
			else self[ varname ] = string.ToColor( tostring( v ) ) end
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

-- Hull
do
	---Returns a HULL_ENUM fitting the hull given.
	---@param vecMin Vector
	---@param vecMax Vector
	---@return number HULL_ENUM
	function util.FindHull( vecMin, vecMax )
		assert(type( vecMin ) == "Vector", "bad argument #1 to FindHull (Vector expected, got " .. type(vecMin) ..")")
		assert(type( vecMax ) == "Vector", "bad argument #2 to FindHull (Vector expected, got " .. type(vecMax) ..")")
		local wide = max(-vecMin.x, -vecMin.y, vecMax.x, vecMax.y)
		local high = vecMax.z - vecMin.z
		if wide <= 16 and high <= 8 then
			return HULL_TINY_CENTERED
		elseif wide <= 24 and high <= 24 then
			return HULL_TINY
		elseif wide <= 40 and high <= 40 then
			return HULL_SMALL_CENTERED
		elseif wide <= 36 and high <= 65 then
			return HULL_MEDIUM
		elseif wide <= 32 and high <= 73 then
			return HULL_HUMAN
		elseif wide <= 36 and high <= 100 then
			return HULL_MEDIUM_TALL
		else
			return HULL_LARGE
		end
	end

	---Returns a HULL_ENUM matching the entitys hull.
	---@param ent Entity
	---@return number HULL_ENUM
	function util.FindEntityHull( entity )
		if entity.GetHull then return entity:GetHull() end
		local mi, ma = entity:OBBMins(), entity:OBBMaxs()
		return FindHull(mi, ma)
	end
end