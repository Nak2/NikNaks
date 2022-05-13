-- Copyright © 2022-2072, Nak, https://steamcommunity.com/id/Nak2/
-- All Rights Reserved. Not allowed to be reuploaded.

local max, min, abs = math.max, math.min, math.abs
local band = bit.band
local ColorToLuminance, ComputeLighting = ColorToLuminance, render and render.ComputeLighting

local function clamp( _in, low, high )
	if _in < low then return low end
	if _in > high then return high end
	return _in
end

-- Makes it easier to read
local NORTH_WEST = 0
local NORTH_EAST = 1
local SOUTH_EAST = 2
local SOUTH_WEST = 3

-- NavDir
local NORTH = 0	-- -Y
local EAST  = 1	-- +X
local SOUTH = 2	-- +Y
local WEST  = 3	-- -X

---@class NNN_Area
local meta_area = {}
meta_area.MetaName = "NNN_Area"
meta_area.__index = meta_area
meta_area.__eq = function( a, b )
	return a.m_id == b.m_id
end
debug.getregistry().NNN_Area = meta_area

---@class NNN_Connection
local meta_connection = {}
meta_connection.__index = meta_connection
meta_connection.MetaName = "NNN_Connection"
debug.getregistry().NNN_Connection = meta_connection

-- Connections meta-functions
do
	---Returns the area it connects to
	---@return NNN_Area
	function meta_connection:GetArea()
		return self.m_area
	end

	---Returns the NavDir
	---@return NavDir
	function meta_connection:GetDirection()
		return self.m_dir
	end

	---Returns the gound height difference between the two areas.
	---@return number
	function meta_connection:GetDifferenceHeight()
		return self.m_height
	end

	---Returns the start-center of the "bridge" between the areas
	---@return Vector
	function meta_connection:GetFrom()
		return self.m_from
	end

	---Returns the end-center of the "bridge" between the areas
	---@return Vector
	function meta_connection:GetTo()
		return self.m_to
	end

	---Returns the length of the areas "connected"
	---@return number
	function meta_connection:GetSize()
		return self.m_size
	end

	---Returns true if the connection is enabled
	---@return boolean
	function meta_connection:IsEnabled()
		return self.m_enabled
	end

	---Allows you to disable or enable the connection
	---@param enable boolean
	---@return self
	function meta_connection:SetEnabled( enable )
		self.m_enabled = enabled ~= false
		self.m_other.m_enabled = enabled ~= false
		return self
	end

	---Returns the height of the bridge between the areas.
	---@return number
	function meta_connection:GetHeight()
		return self.m_height
	end

	---Returns the mirrored connection
	---@return NNN_Connection
	function meta_connection:GetMirrorConnection()
		return self.m_other
	end

	---Returns the distance between the connections
	---@return number
	function meta_connection:GetDistance()
		return self.m_dist
	end
end

-- Areas meta-functions
do
		---Returns the ID
	---@return number
	function meta_area:GetID()
		return self.m_id
	end

	---Returns the center of the area
	---@return Vector
	function meta_area:GetCenter()
		return self.m_center
	end

	---Returns a corner position
	---@param corner_id number
	---@return Vector
	function meta_area:GetCorner( corner_id )
		return self.m_corner[corner_id]
	end

	---Returns the "center" of the area
	---@return Vector
	function meta_area:GetSidePos()
		return self.m_center
	end

	---Returns the normal of the area.
	---@return Vector
	function meta_area:GetNormal()
		return self.m_normal
	end

	---Returns the dot product of the area. (How sloped it is). 1 = perfect flat, 0 = sideways.
	---@return number
	function meta_area:GetFlatness()
		return self.m_flatness or 1
	end

	---Returns the size y of the area
	---@return number
	function meta_area:GetSizeX()
		return self.m_sizex or 0
	end

	---Returns the size X of the area
	---@return number
	function meta_area:GetSizeY()
		return self.m_sizey or 0
	end

	---Returns true if the area has water.
	---@return boolean
	function meta_area:HasWater()
		return self.m_haswater or false
	end

		---Returns the attributeflags for the area
	---@return number
	function meta_area:GetAttributes()
		return self.m_attributeFlags or 0
	end

	---Returns true if the area has the attribute
	---@param flag number
	---@return boolean
	function meta_area:HasAttributes( flag )
		return bit.band(self.m_attributeFlags, flag) ~= 0
	end

	---Sets the attributes to the given flag
	---@param flag number
	function meta_area:SetAttributes( flag )
		self.m_attributeFlags = flag
	end

	---Sets a specific attribute to the area.
	---@param flag number
	function meta_area:SetAttribute( flag, set )
		if set then
			self.m_attributeFlags = bit.bor(self.m_attributeFlags, flag)
		else
			self.m_attributeFlags = bit.band(self.m_attributeFlags, bit.bnot(flag) )
		end
	end

	---Returns the areas place-name. If it has any.
	---@return string|nil
	function meta_area:GetPlace()
		return area.m_directorys
	end
end

-- Areas higer meta-functions
do
	---Returns the Z position of x, y position. If none given, returns the Z of the center.
	---@param x? number
	---@param y? number
	---@return number z
	function meta_area:GetZ( x, y )
		if not x or not y then return self.m_center.z end
		local nw, se = self.m_corner[NORTH_WEST], self.m_corner[SOUTH_EAST]
		local ne, sw = self.m_corner[NORTH_EAST], self.m_corner[SOUTH_WEST]
		local v	= clamp( ( x - nw.x) / (se.x - nw.x ) , 0, 1)
		local u	= clamp( ( y - nw.y) / (se.y - nw.y ) , 0, 1)
		local a = nw.z + u * ( ne.z - nw.z )
		local b = sw.z + u * ( se.z - sw.z )
		return a + v * ( b - a )
	end

		---Returns true if the position is within the area
	---@param pos Vector
	function meta_area:IsWithin( pos, zFuzzy )
		if self.m_maxz < pos.z then return false end -- Pos is above the area
		local nw, se = self.m_corner[0], self.m_corner[2]
		if pos.x < nw.x or pos.x > se.x or pos.y < nw.y or pos.y > se.y then return false end
		local posZ = pos.z + 10 -- Make sure the lookup is a few units over the ground
		return self:GetZ( pos.x, pos.y ) <= posZ
	end

	---Returns the closest point within the area to the given position.
	---@param position Vector
	function meta_area:GetClosestPointOnArea( position )
		local x = clamp(position.x, self.m_corner[0].x, self.m_corner[2].x)
		local y = clamp(position.y, self.m_corner[0].y, self.m_corner[2].y)
		local z = self:GetZ(x,y) -- The ground position
		return Vector(x,y, clamp(position.z, z, self.m_maxz))
	end

	---Returns the closest point on the ground within the area to the given position.
	---@param position Vector
	function meta_area:GetClosestGoundPointOnArea( position )
		local x = clamp(position.x, self.m_corner[0].x, self.m_corner[2].x)
		local y = clamp(position.y, self.m_corner[0].y, self.m_corner[2].y)
		local z = self:GetZ(x,y) -- The ground position
		return Vector(x,y,z)
	end

	---Returns the distance to the position
	---@param position Vector|NNN_Area
	---@return number
	function meta_area:Distance( position )
		if position.MetaName and position.MetaName == meta_area.MetaName then
			position = position:GetClosestPointOnArea( self:GetCenter() )
		end
		return self:GetClosestPointOnArea( position ):Distance( position )
	end

	---Returns the squared distance to the position
	---@param position Vector|NNN_Area
	---@return number
	function meta_area:DistToSqr( position )
		if position.MetaName and position.MetaName == meta_area.MetaName then
			position = position:GetClosestPointOnArea( self:GetCenter() )
		end
		return self:GetClosestPointOnArea( position ):DistToSqr( position )
	end

	---Computes the direction to said point
	---@param point Vector
	---@return NavDir
	function meta_area:ComputeDirection( point )
		local closest = self:GetClosestPointOnArea( point )
		local offset = point - closest
		if abs( offset.x ) > abs( offset.y ) then
			if offset.x >= 0 then
				return SOUTH
			else
				return NORTH
			end
		else
			if offset.y >= 0 then
				return EAST
			else
				return WEST
			end
		end
	end

	function meta_area:ComputeDirection2( point )
		local nw, se = self.m_corner[NORTH_WEST], self.m_corner[SOUTH_EAST]
		if point.x >= nw.x and point.x <= se.x then
			if point.y < nw.y then
				return NORTH
			elseif point.y > se.y then
				return SOUTH
			end
		elseif point.y >= nw.y and point.y <= se.y then
			if point.x < nw.x then
				return WEST
			elseif point.x > se.x then
				return EAST
			end
		end
		local to = point - self.m_center
		if abs(to.x) > abs(to.y) then
			if to.x > 0 then
				return EAST
			end
			return WEST
		else
			if to.y > 0 then
				return SOUTH
			end
			return NORTH
		end
	end


	---Calculates the height difference between the two nnn_areas. Unlike nav, this calculates from the closest point.
	---@param nnn_area NNN_Area
	function meta_area:ComputeGroundHeightChange( nnn_area )
		local a = self:GetClosestGoundPointOnArea( nnn_area.m_center )
		local b = nnn_area:GetClosestGoundPointOnArea( a )
		return b.z - a.z
	end
end

-- Areas <-> Connection functions
do
	local C_UNKNOWN = 0
	local C_SMALLER = 1
	local C_BIGGER	= 2
	local C_MIX		= 3
	function meta_area:HasConnection( nnn_area )
		return nnn_area.m_connections[self.m_id] and self.m_connections[nnn_area.m_id]
	end

	-- Locates the middle between the two areas, and the width
	local function findSidePos(area, area2, dir, debugprint)
		-- Find XY
		local from, to, size
		local _typeA, _typeB
		if dir == NORTH then	-- -X
			local A, B = area.m_corner[NORTH_WEST], area2.m_corner[SOUTH_WEST]
			local AA,BB= area.m_corner[NORTH_EAST], area2.m_corner[SOUTH_EAST]
			local y
			local x = A.x
			if A.y < B.y and AA.y > BB.y then -- We're a bigger area
				y1, y2 = B.y, BB.y
				y = (y1 + y2) / 2
				_typeA = C_BIGGER
				_typeB = C_SMALLER
			elseif A.y > B.y and AA.y < BB.y then -- We're a smaller area
				y1, y2 = A.y, AA.y
				y = (y1 + y2) / 2
				_typeB = C_BIGGER
				_typeA = C_SMALLER
			else	-- One of the sides are outside the other area
				y1, y2 = max( A.y, B.y ), min( AA.y, BB.y )
				y = (y1 + y2) / 2
				_typeA = C_MIX
				_typeB = C_MIX
			end
			size = y1 - y2
			from 	= Vector( x, y, area:GetZ(x, y) )
			to 		= Vector( x, y, area2:GetZ(x, y) )
		elseif dir == SOUTH then	-- +X
			local A, B = area.m_corner[SOUTH_WEST], area2.m_corner[NORTH_WEST]
			local AA,BB= area.m_corner[SOUTH_EAST], area2.m_corner[NORTH_EAST]
			local y1, y2
			local x = A.x
			if A.y < B.y and AA.y > BB.y then -- We're a bigger area
				y1, y2 = B.y, BB.y
				_typeA = C_BIGGER
				_typeB = C_SMALLER
			elseif A.y > B.y and AA.y < BB.y then -- We're a smaller area
				y1, y2 = A.y, AA.y
				_typeB = C_BIGGER
				_typeA = C_SMALLER
			else	-- One of the sides are outside the other area
				y1, y2 = math.max( A.y, B.y ), math.min( AA.y, BB.y )
				_typeA = C_MIX
				_typeB = C_MIX
			end
			local y = (y1 + y2) / 2
			size = y1 - y2
			from 	= Vector( x, y, area:GetZ(x, y) )
			to 		= Vector( x, y, area2:GetZ(x, y) )
		elseif dir == EAST then 	-- -Y
			local A, B = area.m_corner[NORTH_EAST], area2.m_corner[NORTH_WEST]
			local AA,BB= area.m_corner[SOUTH_EAST], area2.m_corner[SOUTH_WEST]
			local x1, x2
			local y = A.y
			if A.x < B.x and AA.x > BB.x then -- We're a bigger area
				x1, x2 = B.x, BB.x
				_typeA = C_BIGGER
				_typeB = C_SMALLER
			elseif A.x > B.x and AA.x < BB.x then -- We're a smaller area
				x1, x2 = A.x, AA.x
				_typeB = C_BIGGER
				_typeA = C_SMALLER
			else	-- One of the sides are outside the other area
				x1, x2 = math.max( A.x, B.x ), math.min( AA.x, BB.x )
				_typeA = C_MIX
				_typeB = C_MIX
			end
			local x = (x1 + x2) / 2
			size = x1 - x2
			from 	= Vector( x, y, area:GetZ(x, y) )
			to 		= Vector( x, y, area2:GetZ(x, y) )
		else	--	WEST			-- +X
			local A, B = area.m_corner[NORTH_WEST], area2.m_corner[NORTH_EAST]
			local AA,BB= area.m_corner[SOUTH_WEST], area2.m_corner[SOUTH_EAST]
			local x1, x2
			local y = A.y
			if A.x < B.x and AA.x > BB.x then -- We're a bigger area
				x1, x2 = B.x, BB.x
				_typeA = C_BIGGER
				_typeB = C_SMALLER
			elseif A.x > B.x and AA.x < BB.x then -- We're a smaller area
				x1, x2 = A.x, AA.x
				_typeB = C_BIGGER
				_typeA = C_SMALLER
			else	-- One of the sides are outside the other area
				x1, x2 = math.max( A.x, B.x ), math.min( AA.x, BB.x )
				_typeA = C_MIX
				_typeB = C_MIX
			end
			local x = (x1 + x2) / 2
			size = x1 - x2
			from 	= Vector( x, y, area:GetZ(x, y) )
			to 		= Vector( x, y, area2:GetZ(x, y) )
		end
		return from, to, abs(size), _typeA or C_UNKNOWN, _typeB or C_UNKNOWN
	end

	local function intermath(x, y, x2, y2)
		local A = y2 - y
		local B = x - x2
		local C = A * x + B * y
		return A, B, C
	end

	local function calcLM( connection )
		local s = connection.m_size / 2
		local _start, _end
		if DIR == SOUTH or DIR == NORTH then
			_start 	= connection.m_from - Vector(0,s,0)
			_end 	= connection.m_from + Vector(0,s,0)
		else
			_start 	= connection.m_from + Vector(s,0,0)
			_end 	= connection.m_from - Vector(s,0,0)
		end
		connection._start = _start
		connection._end = _end
	end

	---Creates a connection between the area and another
	---@param nnn_area NNN_Area
	function meta_area:CreateConnection( nnn_area )
		if self:HasConnection( nnn_area ) then return end
		local closest = nnn_area:GetClosestGoundPointOnArea( self.m_center )
		local dir = self:ComputeDirection( nnn_area.m_center )
		local from, to, size, _typeA, _typeB = findSidePos( self, nnn_area, dir )
		local dist = self:Distance( nnn_area )
		local height = self:ComputeGroundHeightChange( nnn_area )

		-- Connection A
		local A, B
		do
			local connection = {}
			connection.m_area	= nnn_area
			connection.m_dir	= dir
			connection.m_dist	= dist
			connection.m_height	= height
			connection.m_from	= from
			connection.m_to 	= to
			connection.m_size	= size
			connection.m_enabled= true
			connection._TYPE = _typeA
			setmetatable(connection, meta_connection)
			self.m_connections[nnn_area.m_id] = connection
			A = connection
		end
		-- Connection B
		do
			local connection = {}
			connection.m_area	= self
			connection.m_dir	= (dir + 2) % 4
			connection.m_dist	= dist
			connection.m_height	= -height
			connection.m_from	= to
			connection.m_to 	= from
			connection.m_size	= size
			connection.m_enabled= true
			connection._TYPE = _typeB
			setmetatable(connection, meta_connection)
			nnn_area.m_connections[self.m_id] = connection
			B = connection
		end
		-- Tell A about B and revese
		A.m_other = B
		B.m_other = A
		-- Calculate Z the areas touches
		A.m_zheight = math.min( self.m_maxz, nnn_area.m_maxz ) - math.max( A.m_from.z, A.m_to.z )
		B.m_zheight	= A.m_zheight
		-- LineMath
		calcLM(A)
		calcLM(B)
	end

	---Deletes the connection between the two areas.
	---@param nnn_area NNN_Area
	function meta_area:RemoveConnection( nnn_area )
		self.m_connections[nnn_area.m_id] = nil
		nnn_area.m_connections[self.m_id] = nil
	end

	--Deletes all connections
	function meta_area:RemoveAllConnections()
		for id, connection in pairs( self.m_connections ) do
			self:RemoveConnection( connection.m_area )
		end
	end

	-- Commpiles and modifies all connections to the area. This is to help pathfinding.
	function meta_area:CompileAllConnectionSize()
		if true then return end
		-- List of all sides
		local side = {}
		for id, connection in pairs( self.m_connections ) do
			if not side[ connection.m_dir ] then side[ connection.m_dir ] = {} end
			table.insert( side[ connection.m_dir ], connection )
		end

		for NavDir = 0, 3 do
			if not side[NavDir] then continue end
			if #side[NavDir] == 1 then -- Only one connection on this side
				local connection = side[NavDir][1]
				if connection._TYPE == C_SMALLER then -- This is a connection from smaller to bigger connection
					-- We can update the connection-size
					local area_to = connection.m_area
					local nw, se = area_to.m_corner[NORTH_WEST], area_to.m_corner[SOUTH_EAST]
					local size
					if NavDir == NORTH or NavDir == SOUTH then
						size = min( -(nw.y - connection.m_from.y), se.y - connection.m_from.y )
					else
						size = min( connection.m_from.x - nw.x, connection.m_from.x - se.x )
						
					end
					connection.m_size = size
				end
			else

			end
		end
	end

	--Returns a list of all connections (A bit slow as it has to iterate and all all connections to a new table)
	---@return table
	function meta_area:GetAllConnections()
		local t = {}
		for id, connection in pairs(self.m_connections) do
			table.insert(t, connection)
		end
		return t
	end

	--Returns a list of all connections with the area_id being the key.
	---@return table
	function meta_area:GetAllConnectionsWID()
		return self.m_connections
	end

	---Returns the connections for said direction
	---@param NavDir number
	---@return table
	function meta_area:GetConnectionsDir( NavDir )
		local t = {}
		for id, connection in pairs( self.m_connections ) do
			if connection.m_dir == NavDir then table.insert(t, v) end
		end
		return t
	end

	---Returns the connections that has a minimum Z-height
	---@param minimum_height number
	---@return table
	function meta_area:GetConnectionsWithZ( minimum_height )
		local t = {}
		for id, connection in pairs( self.m_connections ) do
			if connection.m_height >= minimum_height then table.insert(t, v) end
		end
		return t
	end
end

-- Save & Load
do
	function meta_area.__save( NNN_Area, bytebuffer )
		bytebuffer:WriteULong(NNN_Area.m_id)
		bytebuffer:WriteVector(NNN_Area.m_corner[0])
		bytebuffer:WriteVector(NNN_Area.m_corner[2])
		bytebuffer:WriteFloat(NNN_Area.m_corner[3].z)
		bytebuffer:WriteFloat(NNN_Area.m_corner[1].z)
		bytebuffer:WriteFloat(NNN_Area.m_maxz)
		bytebuffer:WriteULong(NNN_Area.m_attributeFlags or 0)
		bytebuffer:WriteByte(NNN_Area.m_directory or 0)
		for i = 0, 3 do
			bytebuffer:WriteByte( NNN_Area.m_lightIntensity[i] )
		end
	end

	function meta_area.__load( mesh, bytebuffer )
		local id	= bytebuffer:ReadULong()
		local t 	= mesh:CreateArea( bytebuffer:ReadVector(), bytebuffer:ReadVector(), bytebuffer:ReadFloat(), bytebuffer:ReadFloat(), id )
		t.m_maxz		= bytebuffer:ReadFloat()
		t.m_attributeFlags = bytebuffer:ReadULong()
		t.m_movepoints	= {}
		t.m_hintpoints 	= {}
		t.m_connections_raw = {}
		t.m_directory = bytebuffer:ReadByte()
		if t.m_directory > 0 then
			t.m_directorys = mesh.m_directory[t.m_directory] or "Unknown"
		end
		t.m_lightIntensity = {}
		for i = 0, 3 do
			t.m_lightIntensity[i] = bytebuffer:ReadByte()
		end
		setmetatable(t, meta_area)
		return t
	end

	-- Connections are a bit different, as we save and load all of them
	function meta_connection.__saveAll( mesh, bytebuffer )
		print("Connection Save All")
		-- Collect all connections on the mesh and generate a list.
		local connections = {}
		for id, area in pairs( mesh.m_areas ) do
			for id2, connection in pairs( area.m_connections ) do
				--Make sure the connections don't duplicate
				if connections[id] and connections[id][id2] then continue end
				if connections[id2] and connections[id2][id] then continue end
				if not connections[id] then connections[id] = {} end
				connections[id][id2] = true
			end
		end
		-- Save the list
		--PrintTable(connections)
		bytebuffer:WriteULong( table.Count(connections) )
		for id, tab in pairs( connections ) do
			bytebuffer:WriteULong( id )
			bytebuffer:WriteByte( table.Count(tab) )
			for oid, _ in pairs( tab ) do
				bytebuffer:WriteULong( oid )
			end
		end
	end

	function meta_connection.__loadAll( mesh, bytebuffer )
		local num = bytebuffer:ReadULong()
		for i = 1, num do
			local area = mesh.m_areas[ bytebuffer:ReadULong() ]
			for ii = 1, bytebuffer:ReadByte() do
				local area2 = mesh.m_areas[ bytebuffer:ReadULong() ]
				area:CreateConnection( area2 )
			end
		end
	end
end

-- Debug Render
if CLIENT then
	local w_col = Color(155,155,255,55)
	local a_col = Color(155,155,255,105)
	local mat = Material("vgui/hud/scalablepanel_bgblack_outlinered")
	local mat2 = Material("gui/workshop_rocket.png")
	local mat3 = Material("gui/noicon.png", "noclamp")
	local c_col = Color(55,255,55)
	function meta_area:DebugRender( col )
		
		local PY = (EyeAngles().y - 45) % 360
		local DIR = SOUTH
		if PY < 90 or PY <= 0 then
			DIR = EAST
		elseif PY >= 90 and PY < 180 then
			DIR = NORTH
		elseif PY >= 180 and PY < 270 then
			DIR = WEST
		end
		render.SetMaterial(mat)
		if col then
			render.DrawQuad( self.m_corner[0], self.m_corner[1], self.m_corner[2], self.m_corner[3], col )
		elseif self.m_haswater then
			render.DrawQuad( self.m_corner[0], self.m_corner[1], self.m_corner[2], self.m_corner[3], w_col )
		else
			render.DrawQuad( self.m_corner[0], self.m_corner[1], self.m_corner[2], self.m_corner[3], self.col and color_black or a_col )
		end
		if true then return end
		--if self.m_id ~= 20 then return end
		local i = self.m_id
		for _, connection in pairs( self.m_connections ) do
			if connection.m_dir ~= DIR then continue end
			local _start, _end
			local s = connection.m_size / 2 - 5
			if DIR == SOUTH or DIR == NORTH then
				_start 	= connection.m_from + Vector(0,s,0)
				_end 	= connection.m_from - Vector(0,s,0)
			else
				_start 	= connection.m_from + Vector(s, 0,0)
				_end 	= connection.m_from - Vector(s, 0,0)
			end
			render.SetColorMaterial()
			render.DrawBeam( _start, _end, math.max(connection.m_dist, 16), 0, 1, HSVToColor( i, 0.5, 0.5 ) )
			i = i + 66
			--render.DrawLine( self.m_center, connection.m_from )
			--render.DrawLine( connection.m_from, connection.m_to )
			--render.DrawSprite( connection.m_from, 128, 128 )
		end
		--local v1,v2,v3,v4 = Vector(self.m_corner[0]),Vector(self.m_corner[1]),Vector(self.m_corner[2]),Vector(self.m_corner[3])
		--v1.z = self.m_maxz
		--v2.z = self.m_maxz
		--v3.z = self.m_maxz
		--v4.z = self.m_maxz
		--render.DrawQuad( v4,v3,v2,v1, w_col )
	end
end

-- A* PathFinder functions
do
	local function findIntersectin(A1, A2, B1, B2)
		local dx1, dy1 = A2.x - A1.x, A2.y - A1.y
		local dx2, dy2 = B2.x - B1.x, B2.y - B1.y
		local dx3, dy3 = A1.x - B1.x, A1.y - B1.y
		local d = dx1 * dy2 - dy1 * dx2
		if d == 0 then return end
		local t = (dx2 * dy3 - dy2 * dx3) / d
		if t < 0 then return end
		if t > 1 then return end
		local t2= (dx1 * dy3 - dy1 * dx3) / d
		if t2 <0 or t2 >1 then return end
		return A1.x + t*dx1, A1.y + t * dy1
	end

	-- _start

	---Returns the best position within the conneciton, to reach said position
	---@param position_start Vector
	---@param positin_goal Vector
	---@param size number
	---@return Vector
	function meta_connection:FindBestPathPos( position_start, position_goal, size )
		-- A-Line
		local X, Y = findIntersectin(position_start, position_goal, self._start, self._end)
		if not X then
			return self.m_from
		else
			if self.m_dir == NORTH then
				X = X + size
			elseif self.m_dir == SOUTH then
				X = X - size
			elseif self.m_dir == EAST then
				Y = Y - size
			else
				Y = Y + size
			end
			return Vector(X, Y,self.m_from.z)
		end

	end


	local cost_l, t_cost, open_list, closed_list, move_list = {}, {}, {}, {}, {}
	local open_list_s = {}
	function meta_area:ClearSearchLists()
		cost_l, t_cost, open_list, closed_list, move_list = {}, {}, {}, {}, {}
		open_list_s = {}
	end
	---Sets the cost for pathfinding.
	---@param cost number
	function meta_area:SetCostSoFar(cost)
		cost_l[self:GetID()] = cost
	end
	---Returns the cost so far
	---@return number
	function meta_area:GetCostSoFar()
		return cost_l[self:GetID()] or -1
	end
	---Sets the total cost
	---@param cost number
	function meta_area:SetTotalCost( cost )
		t_cost[self:GetID()] = cost
	end
	---Returns the total cost
	---@return number
	function meta_area:GetTotalCost( )
		return t_cost[self:GetID()] or -1
	end
	---Adds the area to the open list
	function meta_area:AddToOpenList()
		open_list[#open_list + 1] = self
		open_list_s[self:GetID()] = true
	end
	---Returns true if the area is on the open list
	---@return boolean
	function meta_area:IsOpen()
		return open_list_s[self:GetID()] and true or false
	end
	---Retursn true if the open list is empty
	---@return boolean
	function meta_area:IsOpenListEmpty()
		if next(open_list) then return false end
		return true
	end
	local function sorter(a, b)
		return a:GetTotalCost() < b:GetTotalCost()
	end
	---Updates the open list
	function meta_area:UpdateOnOpenList()
		table.sort( open_list, sorter )
	end
	---Pops the open list and returns the kiwest total cost area.
	function meta_area:PopOpenList()
		local a = table.remove(open_list, 1)
		if a then open_list_s[a:GetID()] = nil end
		return a
	end
	---Adds the area to the closed list.
	function meta_area:AddToClosedList()
		closed_list[self:GetID()] = true
	end
	---Returns true if the area is within the closed list.
	---@return boolean
	function meta_area:IsClosed()
		return closed_list[self:GetID()] or false
	end
	---Removes the area from the closed list.
	function meta_area:RemoveFromClosedList()
		closed_list[self:GetID()] = nil
	end
	---Sets the move-type to this area.
	---@param CAP_MOVE number
	function meta_area:SetMoveType( CAP_MOVE )
		move_list[self:GetID()] = CAP_MOVE
	end
	---Returns the move-type to this area.
	---@return number
	function meta_area:GetMoveType()
		return move_list[self:GetID()]
	end
end