-- Copyright © 2022-2072, Nak, https://steamcommunity.com/id/Nak2/
-- All Rights Reserved. Not allowed to be reuploaded.
local NikNaks = NikNaks
local _NodeGraph, _NikNav

function NikNaks._LoadPathOptions()
	-- NodeGraph
	local data = "data/graphs/" .. game.GetMap() .. ".dat"
	local ain = "maps/graphs/" .. game.GetMap() .. ".ain"
	if file.Exists(data, "GAME") then
		_NodeGraph = NikNaks.NodeGraph.LoadAin(data)
	elseif file.Exists(ain, "GAME") then
		_NodeGraph = NikNaks.NodeGraph.LoadAin(ain)
	end

	-- NikNav
	local data = "data/niknav/" .. game.GetMap() .. ".dat"
	if file.Exists(data, "GAME") then
		_NikNav = NikNaks.NikNav.Load( data )
	elseif file.Exists("maps/" .. game.GetMap() .. ".nav", "GAME") then
		_NikNav = NikNaks.NikNav.GenerateFromNav()
		if _NikNav then
			_NikNav:Save()
			NikNaks.Msg("Generated NikNav!")
		else
			NikNaks.Msg("Failed to generate NikNav!")
		end
	end

	hook.Run("NikNak.Navigation.Loaded")
end

-- NodeGrapth Alias and logic
do
	---Returns the AIN version. Should be 37.
	---@return number
	function NikNaks.NodeGraph.GetVersion( )
		return _NodeGraph and _NodeGraph:GetVersion( )
	end

	---Returns the AIN map-version.
	---@return number
	function NikNaks.NodeGraph.GetMapVersion( )
		return _NodeGraph and _NodeGraph:GetMapVersion( )
	end

	---Returns the given ain_node at said ID. 
	---@param id number
	---@return ain_node
	function NikNaks.NodeGraph.GetNode( id )
		return _NodeGraph and _NodeGraph:GetNode( id )
	end

	---Returns the nearest node
	---@param position Vector
	---@param NODE_TYPE? number
	---@param Zone? number
	---@return ain_node
	function NikNaks.NodeGraph.FindNode( position, NODE_TYPE, Zone, HULL )
		return _NodeGraph and _NodeGraph:FindNode( position, NODE_TYPE, Zone, HULL )
	end

	---Returns the nearest node with a connection matching the hull.
	---@param position Vector
	---@param NODE_TYPE? number
	---@param HULL number
	---@param Zone? number
	---@return ain_node
	function NikNaks.NodeGraph.FindNodeWithHull( position, NODE_TYPE, Zone, HULL )
		return _NodeGraph and _NodeGraph:FindNodeWithHull( position, NODE_TYPE, Zone, HULL )
	end

	---Returns the nearest node with said HintType.
	---@param position Vector
	---@param NODE_TYPE? number
	---@param HintType number
	---@param HintGroup? number
	---@param Zone? number
	---@return ain_node
	function NikNaks.NodeGraph.FindHintNode( position, NODE_TYPE, HintType, HintGroup, Zone, HULL)
		return _NodeGraph and _NodeGraph:FindHintNode( position, NODE_TYPE, HintType, HintGroup, Zone, HULL)
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
		return _NodeGraph and _NodeGraph:PathFind( start_pos, end_pos, NODE_TYPE, options, HULL_SIZE, generator )
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
		return _NodeGraph and _NodeGraph:CanMaybeReach( start_pos, end_pos, NODE_TYPE, HULL_SIZE, max_dis ) 
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
		return _NodeGraph and _NodeGraph:PathFindASync( start_pos, end_pos, callback, NODE_TYPE, options, HULL_SIZE, generator )
	end

	---Returns true if the nodegraph for the current map has loaded
	---@return boolean
	function NikNaks.NodeGraph.HasLoaded()
		return _NodeGraph and true or false
	end

	---Tries to reload the NodeGraph
	function NikNaks.NodeGraph.Reload()
		_NodeGraph = NikNaks.NodeGraph.LoadAin()
	end
end

-- NikNaks Alis and logic
do
	---Returns the AIN version. Should be 37.
	---@return number
	function NikNaks.NikNav.GetVersion( )
		return _NikNav and _NikNav:GetVersion( )
	end
	---Returns true if the NikNav has loaded
	---@return boolean
	function NikNaks.NikNav.HasLoaded()
		return _NikNav and true or false
	end

	---Tries to load or generate the NikNav
	function NikNaks.NikNav.Reload()
		if file.Exists("niknav/" .. game.GetMap() .. ".dat", "DATA") then
			_NikNav = NikNaks.NikNav.Load()
		elseif file.Exists("maps/" .. game.GetMap() .. ".nav", "GAME") then -- Generate NikNav
			_NikNav = NikNaks.NikNav.GenerateFromNav()
			if not _NikNav then return end
			_NikNav:Save()
			NikNaks.Msg("Generated NikNav!")
		end
	end

	function NikNaks.NikNav.Unload()
		_NikNav = nil
	end

	---@param start_position Vector
	---@param end_position Vector
	---@param width? number
	---@param height? number
	---@param options? table				A table of options: 
	---@param generator? function 			A function to modify the cost: func( FromArea, ToArea, connection, BitCapability, CurrentCost )
	function NikNaks.NikNav.PathFind( start_position, end_position, width, height, options, generator )
		if not _NikNav then return end
		return _NikNav:PathFind( start_position, end_position, width, height, options, generator )
	end

	---@param start_position Vector
	---@param end_position Vector
	---@param width? number
	---@param height? number
	---@param options? table				A table of options: 
	---@param generator? function 			A function to modify the cost: func( FromArea, ToArea, connection, BitCapability, CurrentCost )
	function NikNaks.NikNav.PathFindASync( start_position, end_position, callback, width, height, options, generator )
		if not _NikNav then return end
		return _NikNav:PathFindASync( start_position, end_position,callback, width, height, options, generator )
	end

	

	---Returns an empty Area ID
	---@return number
	function NikNaks.NikNav.NextAreaID()
		if not _NikNav then return end
		return _NikNav:NextAreaID()
	end

	---Locates the nearest area to the given position
	---@param position Vector
	---@param beneathLimit? number
	---@return NikNav_Area
	function NikNaks.NikNav.GetArea( position, beneathLimit )
		if not _NikNav then return end
		return _NikNav:GetArea( position, beneathLimit )
	end

	---Returns a list of all areas
	---@param table
	function NikNaks.NikNav.GetAllAreas()
		if not _NikNav then return end
		return _NikNav:GetAllAreas( )
	end

	---Returns the area by the given ID
	---@param id number
	---@return NikNav_AREA|nil
	function NikNaks.NikNav.GetAreaByID( id )
		if not _NikNav then return end
		return _NikNav:GetAreaByID( id )
	end

	---Returns the higest ID on the mesh
	---@return number
	function NikNaks.NikNav.GetAreaCount()
		if not _NikNav then return end
		return _NikNav.m_higestID
	end

	---Returns the nearest area
	---@param position Vector
	---@param maxDist? number
	---@param checkLOS? boolean
	---@param hasAttrobutes? number
	---@param matchZone? number
	---@return NikNav_AREA|nil
	function NikNaks.NikNav.GetNearestArea( position, maxDist, checkLOS, hasAttributes, matchZone)
		if not _NikNav then return end
		return _NikNav:GetNearestArea( position, maxDist, checkLOS, hasAttributes, matchZone )
	end


	-- Debug
	if false and CLIENT then
		local t = ents.FindByClass("prop_physics")
		local A = t[1]
		local B = t[2]
		local C = t[3]

		local cost = 0
		local options = {}
		options.StepHeight = 30
		options.ClimbMultiplier = 0.8
		hook.Add("PostDrawOpaqueRenderables", "T", function(a, b)
			if NikNav_Mesh and NikNaks.NikNav then
				NikNav_Mesh:DebugRender()
			else 
				return
			end
			if not A or not B then return end
			local v = A:OBBMaxs() - A:OBBMins()
			local s = SysTime()
			local result = NikNav_Mesh:PathFind( A:GetPos(), B:GetPos(), 32 or math.max(v.x, v.y), v.z, options, nil)
			--local result2 = NodeGraph.PathFind( A:GetPos(), C:GetPos(), NODE_TYPE_GROUND, nil, HULL_HUMAN )
			
			cost = SysTime() - s
			if result == false then
				local ang = EyeAngles()
				ang:RotateAroundAxis( ang:Up(), -90 )
				ang:RotateAroundAxis( ang:Forward(), 90 )
				cam.Start3D2D( A:GetPos() + Vector(0,0, 30), ang, 0.1 )
					draw.DrawText( string.format("Cost: %fms", cost), "TargetID", 0,0, color_white, TEXT_ALIGN_CENTER )
				cam.End3D2D()
				return
			end
			if result == true then
				render.DrawLine( A:GetPos(), B:GetPos(), color_white)
			else
				result:DebugRender()
			end
			if result2 and result2 ~= true and result2 ~= false then
				result2:DebugRender()
			end

			
			local ang = EyeAngles()
			ang:RotateAroundAxis( ang:Up(), -90 )
			ang:RotateAroundAxis( ang:Forward(), 90 )
			cam.Start3D2D( A:GetPos() + Vector(0,0, 30), ang, 0.1 )
				draw.DrawText( string.format("Cost: %fms", cost), "TargetID", 0,0, color_white, TEXT_ALIGN_CENTER )
			cam.End3D2D()
		end)
	end
end