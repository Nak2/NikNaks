-- Copyright © 2022-2072, Nak, https://steamcommunity.com/id/Nak2/
-- All Rights Reserved. Not allowed to be reuploaded.
local NikNaks = NikNaks

local autogen_niknav =		CreateConVar("sv_niknav_autogen", 1, FCVAR_REPLICATED,	"Auto generates NikNav when none is found.")
local autogen_niknav_cl =	CreateConVar("cl_niknav_autogen", 1, FCVAR_REPLICATED,	"Auto generates NikNav on clients when none is found.")

local autoload_niknav =		CreateConVar("sv_niknav_autoload", 0, FCVAR_REPLICATED,	"Auto loads NikNav.")
local autoload_niknav_cl =	CreateConVar("cl_niknav_autoload", 0, FCVAR_REPLICATED,	"Auto loads NikNav on clients.")
local autoload_nodegraph =	CreateConVar("sv_nodegraph_autoload", 0, FCVAR_REPLICATED,	"Auto loads NodeGraph.")
local autoload_nodegraph_cl =CreateConVar("cl_nodegraph_autoload", 0, FCVAR_REPLICATED,	"Auto loads NodeGraph on clients.")

local show_niknav 	=	CLIENT and CreateClientConVar("cl_niknav_show", 0, FCVAR_CHEAT,"Renders NikNav.")
local show_nodegraph=	CLIENT and CreateClientConVar("cl_nodegraph_show", 0, FCVAR_CHEAT,"Renderes NodeGraph.")


local file_niknav 	= "data/niknav/" .. game.GetMap() .. ".dat"
local file_nodegraph= "data/graphs/" .. game.GetMap() .. ".dat"
local file_ain 		= "maps/graphs/" .. game.GetMap() .. ".ain"

local _safe = NikNaks.PostInit or false

-- Loads / generates the NikNav and returns it.
local function init_NikNav()
	-- Make sure auto-load is on.
	local _NikNav
	if file.Exists(file_niknav, "GAME") then
		_NikNav = NikNaks.NikNav.Load( file_niknav:sub(6) )
	elseif file.Exists("maps/" .. game.GetMap() .. ".nav", "GAME") and (SERVER and autogen_niknav:GetBool() or CLIENT and autogen_niknav_cl:GetBool()) then
		_NikNav = NikNaks.NikNav.GenerateFromNav()
		if _NikNav then
			_NikNav:Save()
			NikNaks.Msg("Generated NikNav!")
		else
			NikNaks.Msg("Failed to generate NikNav!")
		end
	end
	if _NikNav then
		hook.Run("NikNav.Loaded")
		return _NikNav
	end
end

-- Loads the Nodegraph and returns it
local function init_NodeGraph()
	local _NodeGraph
	-- Make sure the data has priority, in case they get edited.
	if file.Exists(file_nodegraph, "GAME") then 
		_NodeGraph = NikNaks.NodeGraph.LoadAin(file_nodegraph) or false
		if _NodeGraph then
			hook.Run("NodeGraph.Loaded")
			return _NodeGraph
		end
	end
	-- If something fails to load the data, try the AIN ( If there )
	if file.Exists(file_ain, "GAME") then 
		_NodeGraph = NikNaks.NodeGraph.LoadAin(file_ain) or false
		if _NodeGraph then
			hook.Run("NodeGraph.Loaded")
			return _NodeGraph
		end
	end
end

-- Navigation options w autogen
local navigation = {
	__index = function(k, v)
		if not _safe then return end -- Not safe to generate orl oad yet
		if v == "node" then
			local result = init_NodeGraph()
			rawset( k, v, result or false )
			return result
		elseif v == "mesh" then
			local result = init_NikNav()
			rawset( k, v, result or false )
			return result
		end
	end}
setmetatable(navigation, navigation)

-- Gets called once the map has been loaded.
function NikNaks._LoadPathOptions()
	_safe = true -- Allow gen/load.
	if SERVER and autoload_niknav:GetBool() or CLIENT and autoload_niknav_cl:GetBool() then
		-- Try and load / generate niknav
		local empty = navigation.mesh
	end
	if SERVER and autoload_nodegraph:GetBool() or CLIENT and autoload_nodegraph_cl:GetBool() then
		-- Try and load / generate niknav
		local empty = navigation.node
	end
end

-- NodeGrapth Alias and logic
do
	---Returns the AIN version. Should be 37.
	---@return number
	function NikNaks.NodeGraph.GetVersion( )
		return navigation.node and navigation.node:GetVersion( )
	end

	---Returns the AIN map-version.
	---@return number
	function NikNaks.NodeGraph.GetMapVersion( )
		return navigation.node and navigation.node:GetMapVersion( )
	end

	---Returns the given ain_node at said ID. 
	---@param id number
	---@return ain_node
	function NikNaks.NodeGraph.GetNode( id )
		return navigation.node and navigation.node:GetNode( id )
	end

	---Returns the nearest node
	---@param position Vector
	---@param NODE_TYPE? number
	---@param Zone? number
	---@return ain_node
	function NikNaks.NodeGraph.FindNode( position, NODE_TYPE, Zone, HULL )
		return navigation.node and navigation.node:FindNode( position, NODE_TYPE, Zone, HULL )
	end

	---Returns the nearest node with a connection matching the hull.
	---@param position Vector
	---@param NODE_TYPE? number
	---@param HULL number
	---@param Zone? number
	---@return ain_node
	function NikNaks.NodeGraph.FindNodeWithHull( position, NODE_TYPE, Zone, HULL )
		return navigation.node and navigation.node:FindNodeWithHull( position, NODE_TYPE, Zone, HULL )
	end

	---Returns the nearest node with said HintType.
	---@param position Vector
	---@param NODE_TYPE? number
	---@param HintType number
	---@param HintGroup? number
	---@param Zone? number
	---@return ain_node
	function NikNaks.NodeGraph.FindHintNode( position, NODE_TYPE, HintType, HintGroup, Zone, HULL)
		return navigation.node and navigation.node:FindHintNode( position, NODE_TYPE, HintType, HintGroup, Zone, HULL)
	end

	---A* pathfinding using the NodeGraph.
	---@param start_pos Vector|Entity
	---@param end_pos Vector|Entity
	---@param NODE_TYPE? number
	---@param HULL_SIZE? number
	---@param options? table
	---@param generator? function		-- A funtion that allows you to calculate your own cost: func( node, fromNode, CAP_MOVE, elevator, length )
	---@return LPathFollower|boolean
	function NikNaks.NodeGraph.PathFind( start_pos, end_pos, NODE_TYPE, options, HULL_SIZE, generator )
		return navigation.node and navigation.node:PathFind( start_pos, end_pos, NODE_TYPE, options, HULL_SIZE, generator )
	end

	---A cheap lookup function. Checks to see if we can reach the position using nearby nodes.
	---Note that this use zones and might have false positives on maps with a broken NodeGraph.
	---@param start_pos Vector
	---@param end_pos Vector
	---@param NODE_TYPE? number
	---@param HULL_SIZE? number
	---@param max_dis? number -- Distance to nearest node
	---@return boolean
	function NikNaks.NodeGraph.CanMaybeReach( start_pos, end_pos, NODE_TYPE, HULL_SIZE, max_dis ) 
		return navigation.node and navigation.node:CanMaybeReach( start_pos, end_pos, NODE_TYPE, HULL_SIZE, max_dis ) 
	end

	---A* pathfinding using the NodeGraph. Returns the result in the callback. Calculates 20 paths pr tick.
	---@param start_pos Vector|Entity
	---@param end_pos Vector|Entity
	---@param callback function 		-- Returns the result. LPathFollower or false
	---@param NODE_TYPE? number
	---@param options? table
	---@param HULL_SIZE? number
	---@param generator? function		-- A funtion that allows you to calculate your own cost: func( node, fromNode, CAP_MOVE, elevator, length )
	function NikNaks.NodeGraph.PathFindASync( start_pos, end_pos, callback, NODE_TYPE, options, HULL_SIZE, generator )
		return navigation.node and navigation.node:PathFindASync( start_pos, end_pos, callback, NODE_TYPE, options, HULL_SIZE, generator )
	end

	---Returns true if the nodegraph for the current map has loaded
	---@return boolean
	function NikNaks.NodeGraph.HasLoaded()
		return navigation.node and true or false
	end

	---Tries to reload the NodeGraph
	function NikNaks.NodeGraph.Reload()
		navigation.node = nil
		local empty = navigation.node 
	end

	function NikNaks.NodeGraph.Unload()
		navigation.node = nil
	end

	-- Calling self returns the object
	setmetatable( NikNaks.NodeGraph, NikNaks.NodeGraph )
	function NikNaks.NodeGraph.__call()
		return navigation.node
	end
end

-- NikNaks Alis and logic
do
	---Returns the AIN version. Should be 37.
	---@return number
	function NikNaks.NikNav.GetVersion( )
		return navigation.mesh and navigation.mesh:GetVersion( )
	end
	---Returns true if the NikNav has loaded
	---@return boolean
	function NikNaks.NikNav.HasLoaded()
		return navigation.mesh and true or false
	end

	---Tries to load or generate the NikNav
	function NikNaks.NikNav.Reload()
		navigation.mesh = nil
		local empty = navigation.mesh
	end

	--- Forces the NikNav to generate.
	function NikNaks.NikNav.Generate()
		if file.Exists("maps/" .. game.GetMap() .. ".nav", "GAME") then -- Generate NikNav
			navigation.mesh = NikNaks.NikNav.GenerateFromNav()
			if not navigation.mesh then return end
			navigation.mesh:Save()
			NikNaks.Msg("Generated new NikNav!")
		end
	end

	function NikNaks.NikNav.Unload()
		navigation.mesh = nil
	end

	---@param start_position Vector
	---@param end_position Vector
	---@param width? number
	---@param height? number
	---@param options? table				A table of options: 
	---@param generator? function 			A function to modify the cost: func( FromArea, ToArea, connection, BitCapability, CurrentCost )
	function NikNaks.NikNav.PathFind( start_position, end_position, width, height, options, generator )
		if not navigation.mesh then return end
		return navigation.mesh:PathFind( start_position, end_position, width, height, options, generator )
	end

	---@param start_position Vector
	---@param end_position Vector
	---@param width? number
	---@param height? number
	---@param options? table				A table of options: 
	---@param generator? function 			A function to modify the cost: func( FromArea, ToArea, connection, BitCapability, CurrentCost )
	function NikNaks.NikNav.PathFindASync( start_position, end_position, callback, width, height, options, generator )
		if not navigation.mesh then return end
		return navigation.mesh:PathFindASync( start_position, end_position,callback, width, height, options, generator )
	end

	

	---Returns an empty Area ID
	---@return number
	function NikNaks.NikNav.NextAreaID()
		if not navigation.mesh then return end
		return navigation.mesh:NextAreaID()
	end

	---Locates the nearest area to the given position
	---@param position Vector
	---@param beneathLimit? number
	---@return NikNav_Area
	function NikNaks.NikNav.GetArea( position, beneathLimit )
		if not navigation.mesh then return end
		return navigation.mesh:GetArea( position, beneathLimit )
	end

	---Returns a list of all areas
	---@param table
	function NikNaks.NikNav.GetAllAreas()
		if not navigation.mesh then return end
		return navigation.mesh:GetAllAreas( )
	end

	---Returns the area by the given ID
	---@param id number
	---@return NikNav_AREA|nil
	function NikNaks.NikNav.GetAreaByID( id )
		if not navigation.mesh then return end
		return navigation.mesh:GetAreaByID( id )
	end

	---Returns the higest ID on the mesh
	---@return number
	function NikNaks.NikNav.GetAreaCount()
		if not navigation.mesh then return end
		return navigation.mesh.m_higestID
	end

	---Returns the nearest area
	---@param position Vector
	---@param maxDist? number
	---@param checkLOS? boolean
	---@param hasAttrobutes? number
	---@param matchZone? number
	---@return NikNav_AREA|nil
	function NikNaks.NikNav.GetNearestArea( position, maxDist, checkLOS, hasAttributes, matchZone, minSize)
		if not navigation.mesh then return end
		return navigation.mesh:GetNearestArea( position, maxDist, checkLOS, hasAttributes, matchZone, minSize )
	end

	-- Calling self returns the object
	setmetatable( NikNaks.NikNav, NikNaks.NikNav )
	function NikNaks.NikNav.__call()
		return navigation.mesh
	end
end

if SERVER then return end
-- Debug functions
local sv_cheats = GetConVar("sv_cheats")
hook.Add("PostDrawOpaqueRenderables", "NikNav.Navigation.Debug", function(a, b)
	if not sv_cheats:GetBool() then return end
	if show_niknav:GetBool() then
		if navigation.mesh then
			navigation.mesh:DebugRender()
		end
	end
	if show_nodegraph:GetBool() then
		if navigation.node then
			navigation.node:DebugRender()
		end
	end
end)