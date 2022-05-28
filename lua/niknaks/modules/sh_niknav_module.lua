-- Copyright © 2022-2072, Nak, https://steamcommunity.com/id/Nak2/
-- All Rights Reserved. Not allowed to be reuploaded.
local NikNaks = NikNaks
local max, min, clamp, abs, ceil = math.max, math.min, math.Clamp, math.abs, math.ceil
local band, bor = bit.band, bit.bor
local TraceLine, Vector, util_PointContents, table_remove = util.TraceLine, Vector, util.PointContents, table.remove
local setmetatable = setmetatable
local ColorToLuminance, ComputeLighting = ColorToLuminance, render and render.ComputeLighting

-- Convars
local convar_zheightt = 	CreateConVar("niknav_gen_height_offset", 25, bit.bor(FCVAR_REPLICATED, FCVAR_ARCHIVE),	"How far inside the area the height should be calculated from.")
local convar_automerge= 	CreateConVar("niknav_gen_automerge", 3, bit.bor(FCVAR_REPLICATED, FCVAR_ARCHIVE), 		"Automerges navmesh areas when generating. Number also indecates how many times it should iterate over the mesh.")
local convar_importhint= 	CreateConVar("niknav_gen_import_hints", 1, bit.bor(FCVAR_REPLICATED, FCVAR_ARCHIVE), 	"Imports info_node_hints from BSP when generating.")
local convar_importclimb=	CreateConVar("niknav_gen_import_climb", 1, bit.bor(FCVAR_REPLICATED, FCVAR_ARCHIVE), 	"Imports info_node_climb from BSP when generating.")

local convar_automerge_F=	CreateConVar("niknav_gen_automerge_beta", 0, bit.bor(FCVAR_REPLICATED, FCVAR_ARCHIVE), 	"Ignores connections when compressing. Takes significantly longer.")



-- Nik Naks Navigation
NikNaks.NikNav = {}
NikNaks.NikNav.Version = 0.3

local GRID_SIZE = 800

---@class NikNav_Mesh
local mesh = {}
mesh.__index = mesh
mesh.MetaName = "NikNav_Mesh"
debug.getregistry().NikNav_Mesh = mesh

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

local meta_area = FindMetaTable("NikNav_Area")
local meta_connection = FindMetaTable("NikNav_Connection")
local meta_movep= FindMetaTable("NikNav_MovePoint")
local meta_hintp= FindMetaTable("NikNav_HintPoint")

-- Calculates a normal from 4 vector-points
local function CalcNormal(a, b, c, d)
	-- Calc tri #1
	local u = b - a
	local v = c - a
	local n = Vector(
		u.y * v.z - u.z * v.y,
		u.z * v.x - u.x * v.z,
		u.x * v.y - u.y * v.x )
	local u = c - a
	local v = d - a
	local n2 = Vector(
		u.y * v.z - u.z * v.y,
		u.z * v.x - u.x * v.z,
		u.x * v.y - u.y * v.x )
	return (n + n2):GetNormalized()
end

function NikNaks.NikNav.CreateNew()
	-- Make sure you can't create a nodegraph if entities hasn't been initialised 
	assert(NikNaks.PostInit, "Can't use NikNav before InitPostEntity!")
	local t = {}
	setmetatable(t, mesh)
	t.m_version = NikNaks.NikNav.Version
	t.m_map = file.Size("maps/" .. game.GetMap() .. ".bsp", "GAME")
	t.m_wasonmap = false		-- A flag to tell if the NikNav have been loaded on the map. If this is false, then we need to trace-to-ground the points.
	t.m_areas 	= {}
	t.m_hintpoints 	= {}	-- Hint points are points of activity / interest for the NPC. Antlions use these to burrow, or combine use "window" points.
	t.m_movepoints	= {}	-- A special link between two points the NPC can use. Can be ladders, crawl or a narrow walk line.
	t.m_directory	= {}	-- A list if names for NAV areas
	t.m_higestID = 0
	t._grid = {}
	return t
end

--[[
	TODO: Fix when areas when they reach the limit
]]
-- Lower Mesh Functions
do
	function mesh:GetVersion()
		return self.m_version
	end

	local ceil = ceil
	---Returns an empty Area ID
	---@return number
	function mesh:NextAreaID()
		self.m_higestID = self.m_higestID + 1
		return self.m_higestID
	end

	-- Grid functions
	local function chop(vec)
		return ceil(vec.x / GRID_SIZE), ceil(vec.y / GRID_SIZE)
	end
	---Locates the nearest area to the given position
	---@param position Vector
	---@param beneathLimit? number
	---@return NikNav_Area
	function mesh:GetArea( position, beneathLimit )
		local x,y = chop(position)
		local c, d
		if self._grid[x] and self._grid[x][y] then
			-- Check to see if the area is within
			for id, area in pairs( self._grid[x][y] ) do
				if not area then continue end -- Unknown area?
				if beneathLimit and area.m_pos.z > beneathLimit then continue end
				if area:IsWithin( position ) then return area end -- Position is within this area. Return it.
				-- Log the distance and move on to the next
				local dis = area:DistToSqr( position )
				if d and d < dis then continue end
				d = dis
				c = area
			end
			if c then return c end
		end
		-- No grid found. This is going to be costly.
		for _, area in pairs( self.m_areas ) do
			if area:IsWithin( position ) then return area end -- Position is within this area. Return it.
			-- Log the distance and move on to the next
			local dis = area:DistToSqr( position )
			if d and d < dis then continue end
			d = dis
			c = area
		end
		return c
	end
	---(Interla) Adds an area to the gird.
	---@param area NikNav_Area
	function mesh:AddToGrid( area )
		local x1,y1 = chop( area.m_corner[0] )
		local x2,y2 = chop( area.m_corner[2] )
		-- Add the area to the grid, also add a 1 grid padding, to make it better
		for x = x1 - 1, x2 + 1 do
			for y = y1 - 1, y2 + 1 do
				if not self._grid[x] then self._grid[x] = {} end
				if not self._grid[x][y] then self._grid[x][y] = {} end
				self._grid[x][y][area.m_id] = area
			end
		end
	end
	---(Interla) Removes an area from the gird.
	function mesh:RemoveFromGrid( area )
		local x1,y1 = chop( area.m_corner[0] )
		local x2,y2 = chop( area.m_corner[2] )
		-- Add the area to the grid, also add a 1 grid padding, to make it better
		for x = x1 - 1, x2 + 1 do
			for y = y1 - 1, y2 + 1 do
				if not self._grid[x] then continue end
				if not self._grid[x][y] then continue end
				self._grid[x][y][area.m_id] = nil
			end
		end
	end

	function mesh:GetGrid( position )
		local x,y = chop(position)
		return self._grid[x] and self._grid[x][y] or nil
	end

	---This function re-generated the grid lookup table. This speeds up locating areas and other stuff.
	function mesh:CalculateGrid()
		self._grid = {}
		for id, area in pairs( self.m_areas ) do
			self:AddToGrid( area )
		end
	end

	---Returns a list of all areas
	---@param table
	function mesh:GetAllAreas()
		return self.m_areas
	end

	---Returns the area by the given ID
	---@param id number
	---@return NikNav_AREA|nil
	function mesh:GetAreaByID( id )
		return self.m_areas[id]
	end

	---Returns the higest ID on the mesh
	---@return number
	function mesh:GetAreaCount()
		return self.m_higestID
	end

	-- Checks to see if the line is blocked
	local traceCheck = function( a, b )
		return TraceLine( {
			start = a,
			endpos = b,
			mask = MASK_NPCSOLID_BRUSHONLY
		} ).Hit
	end

	---Returns the nearest area
	---@param position Vector
	---@param maxDist? number
	---@param checkLOS? boolean
	---@param hasAttrobutes? number
	---@param matchZone? number
	---@return NikNav_AREA|nil
	function mesh:GetNearestArea( position, maxDist, checkLOS, hasAttributes, matchZone, minSize)
		maxDist = maxDist or 10000
		local x,y = chop(position)
		local c, d, z
		-- check Grid first
		if self._grid[x] and self._grid[x][y] then
			-- Check to see if the area is within
			for id, area in pairs( self._grid[x][y] ) do
				if not area then continue end -- Unknown area?
				if minSize then
					if area.m_sizex < minSize then continue end
					if area.m_sizey < minSize then continue end
				end
				if matchZone then
					local n = area:GetZone()
					if n >= 0 and n ~= matchZone then
						z = true 
						continue
					end
				end
				if hasAttrobutes and not area:HasAttributes( hasAttributes ) then continue end
				if area:IsWithin( position ) then return area, true end -- Position is within this area. Return it.
				local checkPos = checkLOS and area:GetClosestPointOnArea( position ) or area.m_center
				if maxDist and checkPos:Distance( position ) > maxDist then continue end
				if checkLOS and traceCheck( position, checkPos ) then continue end
				-- Log the distance and move on to the next
				local dis = area:DistToSqr( position )
				if d and d < dis then continue end
				d = dis
				c = area
			end
			if c then return c end
		end
		if z or checkLOS then return end
		-- No grid or area found. This is going to be costly.
		for _, area in pairs( self.m_areas ) do
			if not area then continue end -- Unknown area?
			if matchZone and area.m_zone >= 0 and area.m_zone ~= matchZone then continue end
			if hasAttrobutes and not area:HasAttributes( hasAttributes ) then continue end
			local checkPos = checkLOS and area:GetClosestPointOnArea( position ) or area.m_center
			if maxDist and checkPos:Distance( position ) > maxDist then continue end
			if checkLOS and traceCheck( position, checkPos ) then continue end
			-- Log the distance and move on to the next
			local dis = area:DistToSqr( position )
			if d and d < dis then continue end
			d = dis
			c = area
		end
		return c
	end
end

-- Area Creation and Destruction
do
	local traceHull = function( nw, ne, se, sw )
		local offset = convar_zheightt:GetInt()
		local pos = (nw + ne + se + sw) / 4		-- Get the center
		pos.z = max(nw.z, ne.z, se.z, sw.z) + 1 -- Make sure the higest point to trace here, starts at the higest point.
		local w, h = min((sw.x - nw.x) / 2 - offset, 10), min((ne.y - nw.y) / 2 - offset, 10)
		local mi = Vector(-w,-h, 0)
		local ma = Vector( w, h, 1)
		return util.TraceHull( {
			start = pos + vector_up,
			endpos = Vector(pos.x, pos.y, 32768),
			mins = mi,
			maxs = ma,
			mask = MASK_SOLID_BRUSHONLY
		} )
	end
	---Creates a new area
	---@param corner Vector
	---@param opposite_corner Vector
	---@param nez? number
	---@param swz? number
	---@param force_id? number
	---@return NikNav_Area
	function mesh:CreateArea( corner, opposite_corner, swz, nez, force_id, zone )
		local t = {}
		local nw, se, ne, sw
		if (corner.x + corner.y) < (opposite_corner.x + opposite_corner.y) then
			nw = corner
			se = opposite_corner
			ne = Vector( nw.x, se.y, nez or nw.z )
			sw = Vector( se.x, nw.y, swz or se.z )
		else
			nw = opposite_corner
			se = corner
			ne = Vector( nw.x, se.y, nez or nw.z )
			sw = Vector( se.x, nw.y, swz or se.z )
		end
		if force_id then
			t.m_id		= force_id
			self.m_higestID = max( force_id, self.m_higestID )
		else
			t.m_id		= self:NextAreaID()
		end
		t.m_center	 	= ( nw + se ) / 2
		t.m_corner	 	= { ne, se, sw }
		t.m_corner[0] 	= nw
		t.m_normal 	 	= -CalcNormal(nw, ne, se, sw) 	-- Calc the avage up-normal.
		t.m_flatness	= t.m_normal:Dot( vector_up )	-- How flat is the area is. ( 1 to -1 )
		t.m_maxz		= traceHull(nw, ne, se, sw).HitPos.z
		t.m_attributeFlags = 0
		t.m_movepoints	= {}
		t.m_hintpoints 	= {}
		t.m_connections = {}
		t.m_lightIntensity = {}
		t.m_sizex = se.x - nw.x
		t.m_sizey = se.y - nw.y
		t.m_haswater	= band( util_PointContents( t.m_center + t.m_normal ), CONTENTS_WATER ) == CONTENTS_WATER
		if CLIENT then
			for i = 0, 3 do
				t.m_lightIntensity[i] = ComputeLighting( t.m_corner[i] + t.m_normal, t.m_normal )
			end
		else
			for i = 0, 3 do
				t.m_lightIntensity[i] = 255	-- Servers can't calculate light sadly.
			end
		end
		self.m_areas[t.m_id] = t
		setmetatable(t, meta_area)
		-- Add to grid
		self:AddToGrid( t )
		return t
	end

	---Deletes an area
	---@param NikNav_Area
	function mesh:RemoveArea( area )
		area:RemoveAllConnections() -- Remove all connections to this area.
		self:RemoveFromGrid( area ) -- Remove the area from the grid lookup table.
		-- Make a list of all points near/on this area
		local points = {}
		for _, point in pairs( area.m_hintpoints ) do
			points[#points + 1] = point
		end
		-- Move points got two points, and can be one-way. We need to make sure second-pos gets updated
		for _, point in pairs( self.m_movepoints ) do
			if point.m_area == area or point.m_area_to == area then
				points[#points + 1] = point
			end
		end
		-- Delete the area
		self.m_areas[area.m_id] = nil
		-- Update any points we collected
		for k, point in pairs( points ) do
			point:UpdateArea( self )
		end
	end
end

-- Area Merge functions
do
	---Returns true if the two areas can be merged.
	---@param area NikNav_Area
	---@param area2 NikNav_Area
	---@param fuzzy? number		"Fuzzyness" of the angles.
	---@param checkZ? boolean	Compares the Z height betweeen the two areas as well. On by default.
	---@return boolean
	function mesh:CanMerge(area, area2, fuzzy, checkZ)
		if not area or not area2 then return false end
		if area.m_id == area2.m_id then return false end -- Can't merge itself
		if area.m_directorys or area2.m_directorys then
			if (area.m_directorys or "") ~= (area2.m_directorys or "") then return false end
		end
		local nw = area.m_corner[NORTH_WEST]
		local se = area.m_corner[SOUTH_EAST]
		local nw2 = area2.m_corner[NORTH_WEST]
		local se2 = area2.m_corner[SOUTH_EAST]
		-- Can combine (Check to see if points are close)
		if abs(nw.x - nw2.x) < 1 and abs( se.x - se2.x ) < 1 then
		elseif abs(nw.y - nw2.y) < 1 and abs(se.y - se2.y) < 1 then
		else
			return false
		end
		fuzzy = fuzzy or 0.999
		-- Looks fine, but check angle. We can use "flatness" to check for this.
		if area.m_normal:Dot(area2.m_normal) < fuzzy then return false end
		if abs(area.m_maxz - area2.m_maxz) > 60 then return false end
		if checkZ or checkZ == nil then -- Check the Z height between the two areas.
			if abs( area:ComputeGroundHeightChange( area2 ) ) > 10 then return false end
		end
		return true
	end

	local isClose = function(p,p2)
		return abs(p.x - p2.x) < 1 and abs(p.y - p2.y) < 1
	end

	local function FindAndDeleteConnection( from_area, to_area ) -- Deletes the connection one-way
		-- Delete connection to the area and find the direction.
		for k, connection in pairs( from_area.m_connections ) do
			if connection.m_area == to_area then
				table_remove(from_area.m_connections, k)
				return
			end
		end
	end

	---Tries to merge the two areas together.
	---@param area NikNav_Area
	---@param area2 NikNav_Area
	---@param fuzzy? number		"Fuzzyness" of the angles.
	---@return boolean
	function mesh:MergeAreas(area, area2, fuzzy)
		local isClose = isClose
		if not self:CanMerge(area, area2, fuzzy) then return false end

		local nw	= area.m_corner[NORTH_WEST]
		local se	= area.m_corner[SOUTH_EAST]
		local ne2	=area2.m_corner[NORTH_EAST]
		local sw2	=area2.m_corner[SOUTH_WEST]

		-- Merge area
		if isClose(nw,ne2) then			-- West
			area.m_corner[NORTH_WEST] = area2.m_corner[NORTH_WEST]
			area.m_corner[SOUTH_WEST] = area2.m_corner[SOUTH_WEST]
			nw = area.m_corner[NORTH_WEST]
		elseif isClose(nw,sw2) then		-- North
			area.m_corner[NORTH_WEST] = area2.m_corner[NORTH_WEST]
			area.m_corner[NORTH_EAST] = area2.m_corner[NORTH_EAST]
			nw = area.m_corner[NORTH_WEST]
		elseif isClose(se, ne2) then	-- South
			area.m_corner[SOUTH_WEST] = area2.m_corner[SOUTH_WEST]
			area.m_corner[SOUTH_EAST] = area2.m_corner[SOUTH_EAST]
			se = area.m_corner[SOUTH_EAST]
		else-- isClose(se, sw2) then	-- East
			area.m_corner[SOUTH_EAST] = area2.m_corner[SOUTH_EAST]
			area.m_corner[NORTH_EAST] = area2.m_corner[NORTH_EAST]
			se = area.m_corner[SOUTH_EAST]
		end
		
		-- Recalc area-data
		local ne = area.m_corner[NORTH_EAST]
		local sw = area.m_corner[SOUTH_WEST]
		area.m_center	= ( nw + se ) / 2
		area.m_normal 	= -CalcNormal(nw, ne, se, sw) 	-- Calc the avage up-normal.
		area.m_flatness	= area.m_normal:Dot( vector_up )	-- How flat is the area is. ( 1 to -1 )
		area.m_maxz		= min(area.m_maxz, area2.m_maxz)
		area.m_sizex = se.x - nw.x
		area.m_sizey = se.y - nw.y
		area.m_haswater	= band( util_PointContents( area.m_center + area.m_normal ), CONTENTS_WATER ) == CONTENTS_WATER
		area.m_attributeFlags = bor(area.m_attributeFlags, area2.m_attributeFlags)

		-- Connections holds a lot of data, we need to recreate them all
		local pool = {}
		for _, connection in pairs( area.m_connections ) do
			local other_area = connection:GetArea()
			table.insert(pool, other_area.m_id)
			other_area:RemoveConnection( area )
		end
		for _, connection in pairs( area2.m_connections ) do
			local other_area = connection:GetArea()
			table.insert(pool, other_area.m_id)
			other_area:RemoveConnection( area2 )
		end
		-- Redo connections
		area.m_connections = {}
		for k, area_id in pairs( pool ) do
			if area_id == area.m_id then continue end
			if area_id == area2.m_id then continue end
			if not self.m_areas[area_id] then continue end
			area:CreateConnection( self.m_areas[area_id] )
		end	
		-- Delete other area (This will handle movepoints and hintpoints)
		self:RemoveArea( area2 )
		
		-- Fix the new area to the grid
		self:AddToGrid( area )	
		return true
	end
end

-- Zone
do
	---Generates all area-zones on the map.
	function mesh:GenerateZones()
		-- Create a list of all areas on the mesh.
		local s= SysTime()
		local tab = {}
		for i = 1, self.m_higestID do
			local area = self.m_areas[i]
			if not area then continue end
			tab[i] = area
		end
		-- For each node ..
		local zone = 0
		for i = 1, #tab do
			local id, area = next( tab )
			if not area then break end -- Done
			tab[id] = nil
			area.m_zone = zone
			for id, area in pairs( area:GetAllAreasConnectioned() ) do
				area.m_zone = zone
				tab[id] = nil
			end
			zone = zone + 1
		end
	end
end

-- Place Functions
do
	local isstring = NikNaks.isstring
	-- Locates the place-id
	local function findID( self, place_name )
		for id, str in pairs( self.m_directory ) do
			if str == place_name then
				return id
			end
		end
	end

	local function deleteIfUnused( self, id )
		-- Check to see if other areas use the place-ID
		for _, area in pairs( self.m_areas ) do
			if area.m_directory == id then return end -- At least 1 area is using this place-id.
		end
		-- No areas use this. Delete the place.
		self:DeletePlace(oldid)
	end

	---Changes the place-name. Returns false if it doesn't excist.
	---@param place number|string
	---@param place_name string
	---@return boolean
	function mesh:ChangePlace( place, place_name )
		if isstring( place ) then place = findID( self, id ) end
		if not place or not self.m_directory[place] then return false end
		self.m_directory[place] = place_name
		-- Update all areas with the new place-name
		for _, area in pairs( self.m_areas ) do
			if area.m_directory == place then
				area.m_directorys = place_name
			end
		end
		return true
	end

	---Removes the placename from the area.
	---@param area NikNav_Area
	---@return boolean
	function mesh:RemovePlace( area )
		local oldid = area.m_directory
		if not oldid then return false end
		area.m_directory = nil
		area.m_directorys = nil
		deleteIfUnused( self, oldid)
		return true
	end
	
	---Sets the place-name for the given area. Note; only supports 255 diffrent names.
	---@param area NikNav_Area
	---@param place string|number
	---@return boolean success
	function mesh:SetPlace(area, place )
		-- If place is nil. Then remove it instead.
		if not place_name then
			return self:RemovePlace(area)
		end
		-- Find place as ID and plase_name
		local plase_name = place
		if isstring( place ) then
			place = findID( self, place )
		elseif not self.m_directory[place] then
			return false -- Invalid place-id
		else
			plase_name = self.m_directory[place]
		end
		-- We located the place-name. Set the areas.
		if place then
			area.m_directory = place
			area.m_directorys = place_name
			return true
		end
		-- No place found. Create a new place name
		if #self.m_directory >= 255 then return false end -- We reached the limit
		local id = table.insert( self.m_directory, place_name )
		area.m_directory = id
		area.m_directorys = place_name
		return true
	end

	---Deletes the place from all areas and mesh.
	---@param place string|number
	---@return boolean success
	function mesh:DeletePlace( place )
		-- Find placeID
		if isstring( place ) then
			place = findID( self, place )
		end
		if not place then return false end -- Unable to locate the placeID
		-- Delete all area-data regarding this place.
		for _, area in pairs( self.m_areas ) do
			if area.m_directory == place then
				area.m_directory = nil
				area.m_directorys = nil
			end
		end
		local isLast = #self.m_directory == place
		-- Delete it from directory
		table_remove(self.m_directory, place)
		-- Check if the placename was inbetween others in the list. If so, we need to do some shuffling.
		if isLast then
			for _, area in pairs( self.m_areas ) do 
				if area.m_directory > place then -- For each area with a place-name above the one we deleted
					area.m_directory = area.m_directory - 1 -- Move the place-ID down by one
					area.m_directorys = self.m_directory[area.m_directory] -- Update place-name
				end
			end
		end
	end
end

-- Move and Hint Creation and Destruction
do
	---Creates a move point betweeo two positions. This tells the NPCs that they can use this to traverse between two areas. Like crawling.
	---@param from_pos Vector
	---@param to_pos Vector
	---@param moveflag number
	---@param radius? number
	---@param oneway? boolean
	---@return NikNav_MovePoint
	function mesh:CreateMovePoint( from_pos, to_pos, moveflag, radius, oneway )
		local t = {}
		t.m_id = #self.m_movepoints + 1
		t.m_pos = from_pos
		t.m_endpos = to_pos
		t.m_raidus = radius or 5
		t.m_oneway = oneway or false
		t.m_type = moveflag
		t.m_length = from_pos:Distance( to_pos )
		t.m_enabled = true
		setmetatable(t, meta_movep)
		self.m_movepoints[t.m_id] = t
		t:UpdateArea( self )
		return t
	end

	---Creates a hint point. This can be burrow points, window or other NPC hints.
	---@param position Vector
	---@param hint number
	---@param yaw? number
	---@param fov? number
	---@param hintactivity? number
	---@return NikNav_HintPoint
	function mesh:CreateHintPoint( position, hint, yaw, fov, hintactivity )
		local t = {}
		t.m_id = #self.m_hintpoints + 1
		t.m_pos = position
		t.m_hint = hint
		t.m_yaw = yaw or -1
		t.m_fov = fov or 360
		t.m_hintactivity = hintactivity or ""
		t.m_enabled = true
		self.m_hintpoints[t.m_id] = t
		setmetatable(t, meta_hintp)
		t:UpdateArea( self )
		return t
	end

	---Removes a move point.
	---@param move_point NikNav_MovePoint
	function mesh:RemoveMovePoint( move_point )
		move_point:DecoupleArea()
		self.m_movepoints[move_point.m_id] = nil
	end

	---Removes a move point.
	---@param hint_point NikNav_HintPoint
	function mesh:RemoveHintPoint( hint_point )
		hint_point:DecoupleArea()
		self.m_hintpoints[hint_point.m_id] = nil
	end
end

-- Save / Load
do
	---Loads the NikNav
	---@param filename? string
	---@return NikNav_Mesh|nil
	function NikNaks.NikNav.Load( filename )
		-- Make sure you can't create a nodegraph if entities hasn't been initialised 
		assert(NikNaks.PostInit, "Can't use NikNav before InitPostEntity!")
		filename = filename or "niknav/" .. game.GetMap() .. ".dat"
		local niknav = NikNaks.ByteBuffer.OpenFile(filename, "DATA", true)
		if not niknav then return end -- Unable to open file
		if niknav:ReadULong() ~= 0xCAFEC0DE then return end -- Invalid file
		local mesh = NikNaks.NikNav.CreateNew()
		mesh.m_version = niknav:ReadUShort()
		mesh.m_map = niknav:ReadULong()
		if mesh.m_map ~= file.Size("maps/" .. game.GetMap() .. ".bsp", "GAME") then
			NikNaks.Msg("Warning. This NikNav file was built using a different version than the current map!")
		end
		mesh.m_wasonmap = niknav:ReadBool() -- Unsure if we should keep this.
		-- Load directory
		for i = 1, niknav:ReadByte() do
			mesh.m_directory[i] =  niknav:ReadString()
		end
		-- Load areas
		for i = 1, niknav:ReadULong() do
			meta_area.__load( mesh, niknav )
		end
		-- Read connections
		meta_connection.__loadAll( mesh, niknav )
		-- Calculate the grid
		--mesh:CalculateGrid()
		-- Load movepoints
		for i = 1, niknav:ReadUShort() do
			meta_movep.__load( mesh, niknav )
		end
		-- Load hintpoints
		for i = 1, niknav:ReadUShort() do
			meta_hintp.__load( mesh, niknav )
		end
		if niknav:ReadULong() == 0xCAFEC0DE then
			mesh:GenerateZones()
			return mesh
		end
	end

	---Saves the NikNav
	---@param filename? string
	function mesh:Save( filename )
		filename = filename or "niknav/" .. game.GetMap() .. ".dat"
		local niknav = NikNaks.ByteBuffer()
		niknav:WriteULong( 0xCAFEC0DE )
		niknav:WriteUShort( NikNaks.NikNav.Version )
		niknav:WriteULong( file.Size("maps/" .. game.GetMap() .. ".bsp", "GAME") )
		niknav:WriteBool( self.m_wasonmap )
		-- Write directory
		niknav:WriteByte(#self.m_directory)
		for i = 1, #self.m_directory do
			niknav:WriteString( self.m_directory[i] )
		end
		-- Write areas
		niknav:WriteULong( table.Count(self.m_areas) )
		local c = 0
		local connections = {}
		for _, area in pairs( self.m_areas ) do
			area:__save( niknav )
		end
		-- Write connections
		meta_connection.__saveAll( self, niknav )
		-- Write movepoints
		niknav:WriteUShort( #self.m_movepoints )
		for _, move_p in ipairs( self.m_movepoints ) do
			move_p:__save( niknav )
		end
		-- Write hintpoints
		niknav:WriteUShort( #self.m_hintpoints )
		for _, hint_p in ipairs( self.m_hintpoints ) do
			hint_p:__save( niknav )
		end
		niknav:WriteULong( 0xCAFEC0DE )
		file.CreateDir( string.GetPathFromFilename(filename) ) -- Ensure the dirs are there
		niknav:SaveToFile( filename, true )
	end

	do
		-- Tries to compress the mesh-area with its surrounding
		local function tryAndCompress( mesh, area, fuzzy )
			-- Try compress connections
			for _, connection in pairs( area:GetAllConnections() ) do
				if connection:GetDistance() > 1 then continue end
				local other = connection:GetArea()
				if not other then continue end
				if not mesh:MergeAreas(area, other, fuzzy) then continue end
				return true
			end
			-- Noi connections found. Lookup nearby areas.
			if convar_automerge_F:GetBool() then
				for _, area2 in pairs( mesh:GetGrid( area.m_center ) ) do
					if area:Distance( area2 ) > 1 then continue end
					if not mesh:MergeAreas(area, area2, fuzzy) then continue end
					return true
				end
			end
			return false
		end
		--[[
			TODO: The area-compression is VERY simple. Need to create more use-cases for multiple areas.
		]]

		---Tries to compress areas.
		---@param tries? number		How many times we should try and compress
		---@param fuzzy? number		Fuzzyness of angles comparison. 1= Same anges.
		function mesh:Compress( tries, fuzzy )
			tries = tries or 4
			local changed, n = {}, 1
			for k, v in pairs( self.m_areas ) do
				if tryAndCompress(self, v, fuzzy) then
					changed[n] = v.m_id
					n = n + 1
				end
			end
			if #changed < 1 then return end
			-- Some areas got changed. double check those.
			local b = false
			for i = 1, n do
				local area = self.m_areas[changed[i]]
				if not area then continue end
				b = b or tryAndCompress(self, area, fuzzy)
			end
			-- If the new areas didn't compress, or we ran out of tries; return.
			if not b or tries <= 0 then return end
			-- Run the compress function again.
			self:Compress( tries - 1, fuzzy )
		end
	end
end

--- Parser
do
	-- Parse Funcs
	local function loadPlaceData( NAV, navVersion )
		local place = {}
		local count = NAV:ReadUShort()
		if count > 256 then NikNaks.Msg("[NNav] Nav file got too many named areas?") end
		for i=1, count do
			local len = NAV:ReadUShort()
			table.insert(place, NAV:Read(math.min(len, 256)))
		end
		if navVersion > 11 then
			place.m_hasUnnamedAreas = NAV:ReadByte() ~= 0
		end
		return place
	end

	local function loadArea( NAV, navVersion, mesh )
		local id = NAV:ReadULong()
		-- Attributeflags
		local m_attributeFlags = 0
		if navVersion <= 8 then
			m_attributeFlags = NAV:ReadByte()
		elseif navVersion < 13 then
			m_attributeFlags = NAV:ReadUShort()
		else
			m_attributeFlags = NAV:ReadLong() -- Not UInt? Negative flags?
		end

		local area = mesh:CreateArea( NAV:ReadVector(), NAV:ReadVector(), NAV:ReadFloat(), NAV:ReadFloat(), id )
		area.m_attributeFlags = m_attributeFlags

		-- Check WaterLvl

		-- Load connection to adjacent areas
		area.m_connections_raw = {}
		for d = 0, 3 do
			local count = NAV:ReadULong()
			for i = 0, count - 1 do
				local id = NAV:ReadULong()
				table.insert(area.m_connections_raw, id)
			end
		end

		-- Hiding spots
		local hintPos = {}
		local hidingSpotCount  = NAV:ReadByte()
		if hidingSpotCount > 50 then error("NAV area has over 50 hiding spots!") end
		for i = 1, hidingSpotCount do
			local m_id = NAV:ReadULong()
			local m_pos = NAV:ReadVector()
			local m_flags = NAV:ReadByte()
			if m_flags > 0 then
				table.insert(hintPos, {m_pos, m_flags})
			end
		end

		-- Approach spots (Rev in version 15)
		if navVersion < 15 then
			NAV:Skip( 14 * NAV:ReadByte() )
		end

		-- Encounter paths
		local count = NAV:ReadULong()
		for i = 0, count - 1 do
			NAV:Skip( 10 )
			local spotCount = NAV:ReadByte()
			NAV:Skip( spotCount * 5)
		end

		-- Place Data
		area.m_directory = NAV:ReadUShort()
		if area.m_directory > 0 then
			area.m_directorys = mesh.m_directory[area.m_directory] or "Unknown"
		end
	
		-- Version 6 and below is return
		if navVersion < 7 then return area end
	
		-- Ladder data. TODO: FIX THIS
		for dir = 0, 1 do -- 0 = up, 1 = down, 2 = number of directions
			local count = NAV:ReadULong()
			if count > 50 then error("NAV area has over 50 ladders!") end
			NAV:Skip(count * 4)
		end
	
		-- Version 7 and below is return
		if navVersion < 8 then return area end

		-- MAX_NAV_TEAMS = 2?
		NAV:Skip(8)

		-- Version 10 and below is return
		if navVersion < 11 then return area end

		-- Light data for each corner
		area.m_lightIntensity = {}
		for i = 0, 3 do
			local lInt = clamp(NAV:ReadFloat(), 0, 1)
			if CLIENT and lInt == 1 then
				-- NAV is somewhat broken regarding the lightintensity and always 1.
				local lcolor = ComputeLighting( area.m_corner[i] + area.m_normal, area.m_normal )
				lInt = NikNaks.ColorToLuminance( Color( lcolor.x * 255, lcolor.y * 255, lcolor.z * 255 ) )
			end
			area.m_lightIntensity[i] = lInt
		end

		-- Version 15 and below is return
		if navVersion < 16 then return area end
		-- X360 stuff here
		-- Visible area count.
		local visibleAreaCount = NAV:ReadULong() 
		NAV:Skip(visibleAreaCount * 5 + 4)
		return area, hintPos
	end

	local function canSee( from, to )
		if from:DistToSqr(to) > 518400 then return false end
		return not util.TraceLine( {
			start = from,
			endpos = to,
			mask = MASK_SOLID_BRUSHONLY
		} ).Hit
	end

	local function _2ddis( from, to )
		return math.sqrt( (to.x - from.x)^2 + (to.y - from.y)^2 )
	end


	--[[ NAV Version Cheat Sheet
		5 = Added Place info
		---- Conversion to Src ------
		6 = Added Ladder info
		7 = Areas store ladder ID's so ladders can have one-way connections
		8 = Added earliest occupy times (2 floats) to each area
		9 = Promoted CNavArea's attribute flags to a short
		10 - Added sub-version number to allow derived classes to have custom area data
		11 - Added light intensity to each area
		12 - Storing presence of unnamed areas in the PlaceDirectory
		13 - Widened NavArea attribute bits from unsigned short to int
		14 - Added a bool for if the nav needs analysis
		15 - removed approach areas
		16 - Added visibility data to the base mesh <- This is what cause huuuge lag when loading / generating NAVMesh.
	]]

	-- Converts a list of ID's into connections
	local function PostArea(self)
		for k, area in pairs( self.m_areas ) do
			for _, id in ipairs( area.m_connections_raw ) do
				local other = self.m_areas[id]
				area:CreateConnection( other )
			end
			area.m_connections_raw = nil
		end
	end

	---Generates NikNav, by using NAV and BSP files.
	---@param NAVFile? string The nav file to generate from
	---@param BSPFile? string The map file to generate from
	---@return NikNav_Mesh|nil
	function NikNaks.NikNav.GenerateFromNav( NAVFile, BSPFile )
		-- Make sure you can't create a nodegraph if entities hasn't been initialised 
		assert(NikNaks.PostInit, "Can't use NikNav before InitPostEntity!")
		local NAV, BSP, navVersion
		-- Handle / locate input data
		do
			NAVFile = NAVFile or  "maps/" .. game.GetMap() .. ".nav"
			NAV = NikNaks.ByteBuffer.OpenFile( NAVFile , "GAME")
			if not NAV then return end	-- Unable to locate NAV
			if NAV:ReadULong() ~= 0xFEEDFACE then return end -- Magic number doesn't match
			navVersion = NAV:ReadULong()
			if navVersion < 5 then return end -- NAV is too old

			BSP = NikNaks.Map.ReadBSP( BSPFile )
			if not BSP then return end -- Unable to get BSP
		end
		local self
		local starttime = SysTime()
		-- Parse NAV
		do
			-- sub version
			local subVersion = 0
			if navVersion >= 10 then
				subVersion = NAV:ReadULong()
			end

			-- Size Warning
			if NAV:ReadULong() ~= BSP._size then
				NikNaks.Msg("Warning. This Navigation file was built using a different version of given map!")
			end
		
			-- Start generation
			NikNaks.Msg("Generating NikNav from NAV and BSP ..")
			local m_isAnalyzed = navVersion >= 14 and NAV:ReadByte() ~= 0 or false
			self = NikNaks.NikNav.CreateNew()
		
			-- Parse directory
			for id, placeName in ipairs( loadPlaceData( NAV, navVersion ) ) do
				self.m_directory[id] = placeName
			end

			-- Parse areas
			local count = NAV:ReadULong()
			if count <= 0 then
				NikNaks.Msg("Warning. Nav file got no areas!?")
			end

			local hints = {}
			-- Load areas
			for i = 1, count do
				local area, ahints = loadArea( NAV, navVersion, self )
				for k, v in ipairs( ahints ) do
					table.insert(hints, v)
				end
			end
			-- Post areas
			PostArea( self )
			--[[
				-- Ladders ( Somewhat of a mess tbh )

				-- MarkStairAreas

				-- Load class mesh info
				-- LoadCustomData

				-- WarnIfMeshNeedsAnalysis
			]]
			-- NAV finished. Add hint points. NAV hint points are a bit annoying, as it use a flag. Where BSP is a flat number. So have to toss some data out.
			for _, v in ipairs( hints ) do
				local t = -1
				local n = v[2]
				if band(n, 0x08) ~= 0 then	-- Exposed
					t = 1022
				elseif band(n,0x04) ~= 0 then	-- Idea sniper spot
					t = 1021
				elseif band(n,0x02) ~= 0 then	-- Good snuper spot
					t = 1020
				elseif band(n,0x01) ~= 0 then -- Cover	TODO: Somehow get an FOV for this!
					t = 100
				end
				if t <= 0 then continue end
				self:CreateHintPoint( v[1], t, -1, 360 )
			end
		end
		--Check BSP info nodes and crawl points
		local b_hints = convar_importhint:GetBool()
		local b_climb = convar_importclimb:GetBool()
		if b_hint or n_climb then
			local crawlpoints = {}
			for _, v in pairs( BSP:GetEntities() ) do
				if not v.classname then continue end
				if v.classname == "info_node_hint" or v.classname == "info_node_air_hint" then
					if b_hints and v.hinttype then
						self:CreateHintPoint( v.origin, tonumber(v.hinttype), v.angles.yaw, v.nodefov or 180, v.hintactivity )
					end
				elseif b_climb and v.classname == "info_node_climb" then
					table.insert(crawlpoints, v)
				end
			end
			-- Merge crawlpoints into one line
			for i = 1, #crawlpoints do
				local a = table_remove(crawlpoints, i)
				if not a then continue end
				local l = {a}
				local pos1 = a.origin - Angle(0,a.angles.y,0):Forward() * 13
				for ii = #crawlpoints, 1, -1 do
					local b = crawlpoints[ii]
					if _2ddis(pos1, b.origin) > 50 then continue end
					local pos2 = b.origin - Angle(0,b.angles.y,0):Forward() * 13
					if not canSee(pos1, pos2) then continue end
					l[#l + 1] = b
					table_remove(crawlpoints, ii)
				end
				if #l < 2 then -- This list only got 1 point.
					continue
				end 
				-- Get the higest and lowest points
				local h, o = l[1], l[1]
				for i = 2, #l do
					if h.origin.z < l[i].origin.z then
						h = l[i]
					elseif o.origin.z > l[i].origin.z then
						o = l[i]
					end
				end
				self:CreateMovePoint( o.origin, h.origin, NikNaks.CAP_MOVE_CLIMB, 5, false )
			end
		end
		-- Compress
		if convar_automerge:GetInt() > 0 then
			NikNaks.Msg("Compressing NAV-areas ..")
			local s = SysTime()
			local n = table.Count( self.m_areas )
			self:Compress( convar_automerge:GetInt() )
			NikNaks.Msg((string.format("Compressing took: %fms", SysTime() - s)))
			local n2 = table.Count( self.m_areas )
			local c = 100 - ((n2 / n) * 100)
			NikNaks.Msg("Merged " .. (n - n2) .. " together. Saved " .. c .. "%." )
		end
		-- Calculate grid
		self:CalculateGrid()
		-- Calculate size
		--for k, area in pairs( self.m_areas ) do
		--	area:CompileAllConnectionSize()
		--end
		self:GenerateZones()
		NikNaks.Msg((string.format("NAV + BSP -> NikNav parser took: %fms", SysTime() - starttime)))
		return self
	end
end

-- Generator
do
	local Color = Color
	--[[ NAV Version Cheat Sheet
		5 = Added Place info
		---- Conversion to Src ------
		6 = Added Ladder info
		7 = Areas store ladder ID's so ladders can have one-way connections
		8 = Added earliest occupy times (2 floats) to each area
		9 = Promoted CNavArea's attribute flags to a short
		10 - Added sub-version number to allow derived classes to have custom area data
		11 - Added light intensity to each area
		12 - Storing presence of unnamed areas in the PlaceDirectory
		13 - Widened NavArea attribute bits from unsigned short to int
		14 - Added a bool for if the nav needs analysis
		15 - removed approach areas
		16 - Added visibility data to the base mesh <- This is what cause huuuge lag when loading / generating NAVMesh.
	]]

	local NUM_CORNERS = 4
	-- Loads NAV Place data
	local function loadPlaceData( self, NAV, NAVVersion )
		local place = {}
		local count = NAV:ReadUShort()
		if count > 256 then NikNaks.Msg("[NNav] Nav file got too many named areas?") end
		for i=1, count do
			local len = NAV:ReadUShort()
			place[ i ] = NAV:Read(math.min(len, 256))
		end
		if NAVVersion > 11 then
			place.m_hasUnnamedAreas = NAV:ReadByte() ~= 0
		end
		return place
	end

	-- Loads a NAV area, and converts it to NikNav area
	-- Link: https://github.com/ValveSoftware/source-sdk-2013/blob/0d8dceea4310fde5706b3ce1c70609d72a38efdf/mp/src/game/server/nav_file.cpp#L389 
	local function loadNavArea( self, NAV, NAVVersion )
		local area = {}
		setmetatable(area, meta_area)
		area.m_id = NAV:ReadULong()
		-- Attributeflags
		local m_attributeFlags = 0
		if NAVVersion <= 8 then
			m_attributeFlags = NAV:ReadByte()
		elseif NAVVersion < 13 then
			m_attributeFlags = NAV:ReadUShort()
		else
			m_attributeFlags = NAV:ReadLong() -- Not UInt? Negative flags?
		end

		-- Area
		local nw = NAV:ReadVector()
		local se = NAV:ReadVector()
		local ne = Vector( nw.x, se.y, NAV:ReadFloat() )
		local sw = Vector( se.x, nw.y, NAV:ReadFloat() )
		area.m_center	 = ( nw + se ) / 2
		area.m_corner	 = { ne, se, sw }
		area.m_corner[0] = nw
		area.m_normal 	 = -CalcNormal(nw, ne, se, sw) 		-- Calc the avage normal.
		area.m_flatness	 = area.m_normal:Dot( vector_up )	-- How flat is the area is. ( 1 to -1 )

		-- Check WaterLvl

		-- Load connection to adjacent areas
		area.m_connections = {}
		for d = 0, 3 do
			local count = NAV:ReadULong()
			for i = 0, count - 1 do
				local id = NAV:ReadULong()
				table.insert(area.m_connections, id)
			end
		end

		-- Hiding spots
		local hidingSpotCount  = NAV:ReadByte()
		if hidingSpotCount > 50 then error("NAV area has over 50 hiding spots!") end
		for i = 1, hidingSpotCount do
			local m_id = NAV:ReadULong()
			local m_pos = NAV:ReadVector()
			local m_flags = NAV:ReadByte()
		end

		-- Approach spots (Removed in version 15)
		if NAVVersion < 15 then
			NAV:Skip( 14 * NAV:ReadByte() )
		end

		-- Encounter paths
		local count = NAV:ReadULong()
		for i = 0, count - 1 do
			NAV:Skip( 10 )
			local spotCount = NAV:ReadByte()
			NAV:Skip( spotCount * 5)
		end

		-- Place Data
		local entry = NAV:ReadUShort()
		if entry > 0 then
			area.m_directory = placeDirectory[entry]
		end
	
		-- Version 6 and below is return
		if NAVVersion < 7 then return area end
	
		-- Ladder data. TODO: FIX THIS
		for dir = 0, 1 do -- 0 = up, 1 = down, 2 = number of directions
			local count = NAV:ReadULong()
			if count > 50 then error("NAV area has over 50 ladders!") end
			NAV:Skip(count * 4)
		end
	
		-- Version 7 and below is return
		if NAVVersion < 8 then return area end

		-- MAX_NAV_TEAMS = 2?
		NAV:Skip(8)

		-- Version 10 and below is return
		if NAVVersion < 11 then return area end

		-- Light data for each corner
		area.m_lightIntensity = {}
		for i = 0, NUM_CORNERS - 1 do
			local lInt = clamp(NAV:ReadFloat(), 0, 1)
			if CLIENT and lInt == 1 then
				-- NAV is somewhat broken regarding the lightintensity and always 1.
				local lcolor = ComputeLighting( area.m_corner[i] + area.m_normal, area.m_normal )
				lInt = ColorToLuminance( Color( lcolor.x * 255, lcolor.y * 255, lcolor.z * 255 ) )
			end
			area.m_lightIntensity[i] = lInt
		end

		-- Version 15 and below is return
		if NAVVersion < 16 then return area end
		-- X360 stuff here
		-- Visible area count.
		local visibleAreaCount = NAV:ReadULong() 
		NAV:Skip(visibleAreaCount * 5 + 4)
		return area
	end
end

-- Client debug render
if CLIENT then	
	function mesh:DebugRender()
		local lp = LocalPlayer():GetPos()
		local lpv = EyeVector()
		cam.IgnoreZ( false )
		local x,y = math.ceil(lp.x / GRID_SIZE), math.ceil(lp.y / GRID_SIZE)
		if self._grid[x] and self._grid[x][y] then
			for id, area in pairs( self._grid[x][y] ) do
				local v = (lp - area.m_center):GetNormalized()
				local n = v:Dot(lpv)
				if n > 0  then continue end
				area:DebugRender()
			end
		else
			for _, areas in pairs( self.m_areas ) do
				local v = (lp - areas.m_center):GetNormalized()
				local n = v:Dot(lpv)
				local dis = areas.m_center:DistToSqr(lp)
				if n > 0 and dis > 300000 then continue end
				if dis > 7400400 then continue end
				areas:DebugRender()
			end
		end
		cam.IgnoreZ( false )
		for _, movep in pairs( self.m_movepoints ) do
			--PrintTable(movep)
			movep:DebugRender()
		end
		for _, hintp in pairs( self.m_hintpoints ) do
			local v = (lp - hintp.m_pos):GetNormalized()
			local n = v:Dot(lpv)
			if n > 0 then continue end
			if hintp.m_pos:DistToSqr(lp) > 3400400 then continue end
			hintp:DebugRender()
		end
	end
end
