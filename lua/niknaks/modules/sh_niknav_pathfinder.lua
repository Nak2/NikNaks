-- Copyright © 2022-2072, Nak, https://steamcommunity.com/id/Nak2/
-- All Rights Reserved. Not allowed to be reuploaded.

local band = bit.band
local mesh = FindMetaTable("NikNav_Mesh")

-- A* PathFinder
do
	local connectionName = FindMetaTable("NikNav_Connection").MetaName
	local LPFMeta = FindMetaTable("LPathFollower")
	--	Each connection hold direction, distance and valid-move flags
	--	+------+       +------+
	--  |      |  DIR  |      |
	--  |      |  DIS  |      |
	--  +------+       +------+
	--
	--	Distance is some-times not zero, and therefor we need to add the connection-distance.
	--

	-- A "guess" cost using a connection
	local function heuristic_cost_estimate( start, goal, connection )
		if connection.m_dir == NORTH or connection.m_dir == SOUTH then
			return (start:GetSizeX() + goal:GetSizeX()) / 2 + connection.m_dist
		else
			return (start:GetSizeY() + goal:GetSizeY()) / 2 + connection.m_dist
		end
	end
	-- A "guess" cost using distance alone
	local function heuristic_cost_estimate_dis( start, goal )
		return start:Distance( goal )
	end
	
	local function reconstruct_path( cameFrom, current, start_position, end_position, size, def )
		local path = LPFMeta.CreatePathFollower( start_position )
		local end_area = current
		-- Trace back from end to start
		local tab, n = {}, 0
		local LP = end_position
		while ( cameFrom[ current ] ) do
			local move_type, connection = cameFrom[ current ][3], cameFrom[ current ][2]
			current = cameFrom[ current ][1]
			local is_connection = connection.MetaName == connectionName
			local p
			if is_connection then
				p = connection:FindBestPathPos( LP, start_position, size )
				LP = p
			else
				if connection.m_area == current then
					p = connection.m_endpos
					n = n + 1
					tab[n] = {p, move_type}
					p = connection.m_pos
					-- m_endpos
					LP = p
				end
			end
			if not p then continue end
			n = n + 1
			tab[n] = {p, def}
		end
		-- Create segments from start to end
		LP = start_position
		for i = n, 1, -1 do
			local pos = tab[i][1]
			path:AddSegment(LP, pos, 0, tab[i][2])
			LP = pos
		end
		path:AddSegment(LP, end_position, 0, def)
		return path
	end

	--[[
		Tries to A* pathfind to the location.
		true = Same Area
		false = Unable to pathfind at all
		table = List of Areas from goal towards the start
	]]
	local function AStart(area_start, area_end, width, height, options, generator, start_position, end_position, SB, EB )
		if not area_start or not area_end then return false end -- No valid pathfind points
		if area_start == area_end then return true end	-- Same area
		height = height or 10
		-- Clear Data
		area_start:ClearSearchLists()
		area_start:AddToOpenList()
		local cameFrom = {} -- [Area or Move_Point] = {From, Connection}
		area_start:SetCostSoFar(0)
		area_start:SetTotalCost( heuristic_cost_estimate_dis( area_start, area_end ) )
		area_start:UpdateOnOpenList()

		local maxDistance 		= options.MaxDistance or 100000
		local BitCapability 	= options.BitCapability or CAP_MOVE_GROUND
		local JumpMultiplier 	= options.JumpMultiplier or 0.8
		local IgnoreWater 		= options.IgnoreWater or false
		local StepHeight 		= math.abs( options.StepHeight or 18 )
		local ClimbMultiplier	= options.ClimbMultiplier or 0.6

		if options.ClimbMultiplier then
			BitCapability = bit.bor( BitCapability, CAP_MOVE_CLIMB )
		end

		--local canWalk 	= band( BitCapability, CAP_MOVE_GROUND )	~= 0
		local canFly 	= band( BitCapability, CAP_MOVE_FLY )		~= 0
		local canClimb 	= band( BitCapability, CAP_MOVE_CLIMB )		~= 0
		local canJump 	= band( BitCapability, CAP_MOVE_JUMP )		~= 0
		local JumpHeight = canJump and abs( options.JumpHeight or 0 )
		local JumpDown = options.JumpDown and -abs(options.JumpDown) or -100
		local SF = SB

		while not area_start:IsOpenListEmpty()  do
			local current = area_start:PopOpenList()
			if ( current == area_end ) then
				return reconstruct_path(cameFrom, current, start_position, end_position, width, canFly and CAP_MOVE_FLY or CAP_MOVE_GROUND)
			end
			current:AddToClosedList()
			-- Check areas
			for id, connection in pairs( current:GetAllConnections(  ) ) do
				-- m_dir		Direction
				-- m_area		area 
				-- m_from		Center Position From
				-- m_height		Height difference between the two areas
				-- m_dist		Distance in-between the areas
				-- m_zheight	How much of the Z-height the areas share
				-- m_other		The mirrored connection
				-- m_to			Center position on the other area (If distance is 0, the same as m_from)
				-- m_size		How wide the connection is
				-- m_enabled	If the connection is enabled.

				-- Check if connection is enabled
				if not connection.m_enabled then continue end
				if connection.m_size < width then continue end
				if connection.m_zheight < height then continue end
				local mul, move_type = 1
				if canFly then
					move_type = CAP_MOVE_FLY
				else
					-- JumpDown check
					if connection.m_height < -StepHeight then 
						if not canJump or connection.m_height < JumpDown then
							continue
						end
						move_type = CAP_MOVE_JUMP
						mul = JumpMultiplier
					elseif connection.m_height > StepHeight then
						if not canJump or connection.m_height > JumpHeight then
							continue
						end
						move_type = CAP_MOVE_JUMP
						mul = JumpMultiplier
					else
						move_type = CAP_MOVE_GROUND
					end
				end
				local dir = connection.m_dir
				local neighbor = connection.m_area
				if not neighbor then continue end -- Invalid neighbor?	
				if not IgnoreWater and neighbor.m_haswater then continue end -- This area has water
				-- Cost calculator
				local newCostSoFar, h_cost
				if SF then -- The first area, is the one we start in. Cost from here should not be from center, but from the start_position
					h_cost = heuristic_cost_estimate_dis(neighbor, start_position) * mul
					SF = false
				else
					h_cost = heuristic_cost_estimate( current, neighbor, connection ) * mul
				end
				if not generator then -- Custom generator
					newCostSoFar = current:GetCostSoFar() + h_cost
				else -- Default generator
					-- TODO: Elevator? Check L4D elevator maps and what they are.
					local n = generator( current, neighbor, connection, BitCapability, h_cost )
					if n < 0 then continue end
					newCostSoFar = current:GetCostSoFar() + n
				end
				if newCostSoFar < 0 or (maxDistance and newCostSoFar > maxDistance) then -- Check if we should continue this path.
					continue
				end

				if ( neighbor:IsOpen() or neighbor:IsClosed() ) and neighbor:GetCostSoFar() <= newCostSoFar then
					-- This node is already open/close and the cost is shorter
					continue
				else
					neighbor:SetCostSoFar( newCostSoFar );
					neighbor:SetTotalCost( newCostSoFar + heuristic_cost_estimate_dis( neighbor, area_end ) )
					
					if ( neighbor:IsClosed() ) then
						neighbor:RemoveFromClosedList()
					end
					if ( neighbor:IsOpen() ) then
						// This area is already on the open list, update its position in the list to keep costs sorted
						neighbor:UpdateOnOpenList()
					else
						neighbor:AddToOpenList()
					end
					cameFrom[ neighbor ] = { current, connection, move_type }
				end
			end
			-- Check movepoints
			if not next( current.m_movepoints ) then continue end
			for id, move_point in pairs( current.m_movepoints ) do
				if not move_point:IsEnabled() then continue end
				if band(move_point.m_type, BitCapability) == 0 then continue end -- Unable to use this connection
				local neighbor
				if move_point.m_area_to == current then
					neighbor = move_point.m_area
				else
					neighbor = move_point.m_area_to
				end
				-- Find move type
				local mul,move_type = 1
				if canFly and band( move_point.m_type, CAP_MOVE_FLY ) ~= 0 then
					move_type = CAP_MOVE_FLY
				elseif band( move_point.m_type, CAP_MOVE_GROUND ) ~= 0 then
					move_type = CAP_MOVE_GROUND
				elseif canJump and band( move_point.m_type, CAP_MOVE_JUMP) then
					move_type = CAP_MOVE_JUMP
					mul = JumpMultiplier
				elseif canClimb then
					move_type = CAP_MOVE_CLIMB
					mul = ClimbMultiplier
				else		-- Unable to use this??
					continue
				end
				-- Cost
				local cost = move_point.m_length * mul
				local newCostSoFar
				if not generator then -- Custom generator
					newCostSoFar = current:GetCostSoFar() + cost
				else -- Default generator
					-- TODO: Elevator? Check L4D elevator maps and what they are.
					local n = generator( current, neighbor, move_point, BitCapability, cost )
					if n < 0 then continue end
					newCostSoFar = current:GetCostSoFar() + n
				end
				if newCostSoFar < 0 or (maxDistance and newCostSoFar > maxDistance) then -- Check if we should continue this path.
					continue
				end
				if ( neighbor:IsOpen() or neighbor:IsClosed() ) and neighbor:GetCostSoFar() <= newCostSoFar then
					-- This node is already open/close and the cost is shorter
					continue
				else
					neighbor:SetCostSoFar( newCostSoFar );
					neighbor:SetTotalCost( newCostSoFar + heuristic_cost_estimate_dis( neighbor, area_end ) )
					
					if ( neighbor:IsClosed() ) then
						neighbor:RemoveFromClosedList()
					end
					if ( neighbor:IsOpen() ) then
						// This area is already on the open list, update its position in the list to keep costs sorted
						neighbor:UpdateOnOpenList()
					else
						neighbor:AddToOpenList()
					end
					cameFrom[ neighbor ] = { current, move_point, move_type }
				end
			end
		end
		return false
	end

	---Generates a path from point A to point B
	--- Options:
	---	options.JumpMultiplier = 0.6		How much the NPC likes to jump. Default: 0.6
	---	options.BitCapability = 0x0000		What the NPC can do: Flying, walking, climbing .. ect. Note: Will always choose flying over all others
	---	options.MaxDistance = 100000		Max distance to calculate
	--- options.IgnoreWater = false			If true, will allow to pathfind using water
	---@param start_position Vector
	---@param end_position Vector
	---@param width? number
	---@param height? number
	---@param options? table				A table of options: 
	---@param generator? function 			A function to modify the cost: func( FromArea, ToArea, connection, BitCapability, CurrentCost )
	function mesh:PathFind( start_position, end_position, width, height, options, generator )
		local start_area, SB = self:GetNearestArea( start_position, 600, true )
		if not start_area then return false end

		local end_area, EB = self:GetNearestArea( end_position, 600, true )
		if not end_area then return false end

		options = options or {}
		options.BitCapability = options.BitCapability or CAP_MOVE_GROUND
		local result = AStart(start_area, end_area, width, height, options, generator, start_position, end_position, SB, EB )
		if result == false then return false end
		if result == true then
			local fly = bit.band( options.BitCapability, CAP_MOVE_FLY ) ~= 0
			local p = LPFMeta.CreatePathFollower( start_position )
			local s = p:AddSegment(start_position, end_position, 0, fly and CAP_MOVE_FLY or CAP_MOVE_GROUND)
			p._generator = generator
			p._MaxDistance = options.MaxDistance
			return p
		else
			return result
		end
	end

	---Same as PathFind, but sets some parameters
	---@param start_position Vector
	---@param end_position Vector
	---@param width? number
	---@param height? number
	---@param options? table				A table of options: 
	---@param generator? function 			A function to modify the cost: func( FromArea, ToArea, connection, BitCapability, CurrentCost )
	function mesh:PathFindSmart( start_position, end_position, width, height, options, generator )
		options = options or {}
		if options.MaxDistance then
			options.MaxDistance = min( options.MaxDistance, start_position:Distance(end_position) * 2  )
		else
			options.MaxDistance = start_position:Distance(end_position) * 2
		end
		return self:PathFind( start_position, end_position, width, height, options, generator )
	end
end