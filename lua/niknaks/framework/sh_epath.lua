-- Copyright © 2022-2072, Nak, https://steamcommunity.com/id/Nak2/
-- All Rights Reserved. Not allowed to be reuploaded.
local NikNaks = NikNaks

local autoload_nodegraph =	CreateConVar( "sv_nodegraph_autoload", 0, FCVAR_REPLICATED,	"Auto loads NodeGraph." )
local autoload_nodegraph_cl = CreateConVar( "cl_nodegraph_autoload", 0, FCVAR_REPLICATED,	"Auto loads NodeGraph on clients." )

local show_nodegraph = CLIENT and CreateClientConVar( "cl_nodegraph_show", 0, FCVAR_CHEAT, "Renderes NodeGraph." )

local file_nodegraph = "data/graphs/" .. game.GetMap() .. ".dat"
local file_ain 		 = "maps/graphs/" .. game.GetMap() .. ".ain"

local _safe = NikNaks.PostInit or false

-- Loads the Nodegraph and returns it
local function init_NodeGraph()
	local _NodeGraph

	-- Make sure the data has priority, in case they get edited.
	if file.Exists( file_nodegraph, "GAME" ) then
		_NodeGraph = NikNaks.NodeGraph.LoadAin( file_nodegraph ) or false
		if _NodeGraph then
			hook.Run( "NodeGraph.Loaded" )
			return _NodeGraph
		end
	end

	-- If something fails to load the data, try the AIN ( If there )
	if file.Exists( file_ain, "GAME" ) then
		_NodeGraph = NikNaks.NodeGraph.LoadAin( file_ain ) or false
		if _NodeGraph then
			hook.Run( "NodeGraph.Loaded" )
			return _NodeGraph
		end
	end
end

-- Navigation options w autogen
local navigation = {
	__index = function( k, v )
		if not _safe then return end -- Not safe to generate orl oad yet
		if v == "node" then
			local result = init_NodeGraph()
			rawset( k, v, result or false )
			return result
		end
	end }
setmetatable( navigation, navigation )

-- Gets called once the map has been loaded.
function NikNaks._LoadPathOptions()
	_safe = true -- Allow gen/load.
	if SERVER and autoload_nodegraph:GetBool() or CLIENT and autoload_nodegraph_cl:GetBool() then
		-- Try and load / generate niknav
		local _ = navigation.node
	end
end

-- NodeGrapth Alias and logic
do
	--- Returns the AIN version. Should be 37.
	--- @return number
	function NikNaks.NodeGraph.GetVersion()
		return navigation.node and navigation.node:GetVersion()
	end

	--- Returns the AIN map-version.
	--- @return number
	function NikNaks.NodeGraph.GetMapVersion()
		return navigation.node and navigation.node:GetMapVersion()
	end

	--- Returns the given ain_node at said ID. 
	--- @param id number
	--- @return ain_node
	function NikNaks.NodeGraph.GetNode( id )
		return navigation.node and navigation.node:GetNode( id )
	end

	--- Returns the nearest node
	--- @param position Vector
	--- @param NODE_TYPE? number
	--- @param Zone? number
	--- @return ain_node
	function NikNaks.NodeGraph.FindNode( position, NODE_TYPE, Zone, HULL )
		return navigation.node and navigation.node:FindNode( position, NODE_TYPE, Zone, HULL )
	end

	--- Returns the nearest node with a connection matching the hull.
	--- @param position Vector
	--- @param NODE_TYPE? number
	--- @param HULL number
	--- @param Zone? number
	--- @return ain_node
	function NikNaks.NodeGraph.FindNodeWithHull( position, NODE_TYPE, Zone, HULL )
		return navigation.node and navigation.node:FindNodeWithHull( position, NODE_TYPE, Zone, HULL )
	end

	--- Returns the nearest node with said HintType.
	--- @param position Vector
	--- @param NODE_TYPE? number
	--- @param HintType number
	--- @param HintGroup? number
	--- @param Zone? number
	--- @return ain_node
	function NikNaks.NodeGraph.FindHintNode( position, NODE_TYPE, HintType, HintGroup, Zone, HULL )
		return navigation.node and navigation.node:FindHintNode( position, NODE_TYPE, HintType, HintGroup, Zone, HULL )
	end

	--- A* pathfinding using the NodeGraph.
	--- @param start_pos Vector|Entity
	--- @param end_pos Vector|Entity
	--- @param NODE_TYPE? number
	--- @param HULL_SIZE? number
	--- @param options? table
	--- @param generator? function		-- A funtion that allows you to calculate your own cost: func( node, fromNode, CAP_MOVE, elevator, length )
	--- @return LPathFollower|boolean
	function NikNaks.NodeGraph.PathFind( start_pos, end_pos, NODE_TYPE, options, HULL_SIZE, generator )
		return navigation.node and navigation.node:PathFind( start_pos, end_pos, NODE_TYPE, options, HULL_SIZE, generator )
	end

	--- A cheap lookup function. Checks to see if we can reach the position using nearby nodes.
	--- Note that this use zones and might have false positives on maps with a broken NodeGraph.
	--- @param start_pos Vector
	--- @param end_pos Vector
	--- @param NODE_TYPE? number
	--- @param HULL_SIZE? number
	--- @param max_dis? number -- Distance to nearest node
	--- @return boolean
	function NikNaks.NodeGraph.CanMaybeReach( start_pos, end_pos, NODE_TYPE, HULL_SIZE, max_dis )
		return navigation.node and navigation.node:CanMaybeReach( start_pos, end_pos, NODE_TYPE, HULL_SIZE, max_dis )
	end

	--- A* pathfinding using the NodeGraph. Returns the result in the callback. Calculates 20 paths pr tick.
	--- @param start_pos Vector|Entity
	--- @param end_pos Vector|Entity
	--- @param callback function 		-- Returns the result. LPathFollower or false
	--- @param NODE_TYPE? number
	--- @param options? table
	--- @param HULL_SIZE? number
	--- @param generator? function		-- A funtion that allows you to calculate your own cost: func( node, fromNode, CAP_MOVE, elevator, length )
	function NikNaks.NodeGraph.PathFindASync( start_pos, end_pos, callback, NODE_TYPE, options, HULL_SIZE, generator )
		return navigation.node and navigation.node:PathFindASync( start_pos, end_pos, callback, NODE_TYPE, options, HULL_SIZE, generator )
	end

	--- Returns true if the nodegraph for the current map has loaded.
	--- @return boolean
	function NikNaks.NodeGraph.HasLoaded()
		return navigation.node and true or false
	end

	--- Tries to reload the NodeGraph.
	function NikNaks.NodeGraph.Reload()
		navigation.node = nil
		local _ = navigation.node
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

if SERVER then return end

-- Debug functions
local sv_cheats = GetConVar( "sv_cheats" )
hook.Add( "PostDrawOpaqueRenderables", "NikNav.Navigation.Debug", function()
	if not sv_cheats:GetBool() then return end
	if show_nodegraph:GetBool() and navigation.node then
		navigation.node:DebugRender()
	end
end )
