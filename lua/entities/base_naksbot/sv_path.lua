
local max, abs = math.max, math.abs
NikNaks()
-- Path Type
do
	local defaultType
	if file.Exists("data/graphs/" .. game.GetMap() .. ".dat", "GAME") then
		defaultType = PATHTYPE_NIKNAV
	elseif file.Exists("maps/" .. game.GetMap() .. ".nav", "GAME") then
		defaultType = PATHTYPE_NAV
	elseif file.Exists("maps/graphs/" .. game.GetMap() .. ".ain", "GAME") then
		defaultType = PATHTYPE_AIN
	else
		defaultType = PATHTYPE_NONE
	end

	---Sets the pathtype of the entity
	---@param PATH_TYPE number
	function ENT:SetPathType( PATH_TYPE )
		self._pathtype = PATH_TYPE
	end

	---Returns the pathtype the entity use
	---@return number
	function ENT:GetPathType()
		return self._pathtype or defaultType
	end
end

-- NodeGraph and NikNav
do
	---Sets the NodeGraph and makes the entity use it.
	---@param NodeGraph NodeGraph
	function ENT:SetNodeGraph( NodeGraph )
		self._pathtype = PATHTYPE_AIN
		self._nodegraph = NodeGraph
	end
end

-- TODO: Add other pathtype options here

-- NPC Capabilities
do
	---Adds capabilities
	---@param capabilities number
	function ENT:CapabilitiesAdd( capabilities )
		self._cap = bit.bor( self._cap or 0, capabilities )
	end
	---Removes all capabilities
	function ENT:CapabilitiesClear( )
		self._cap = 0
	end
	---Returns capabilities
	---@return number
	function ENT:CapabilitiesGet( )
		return self._cap or 0
	end
	---Removes a capability
	---@param capabilities number
	function ENT:CapabilitiesRemove( capabilities )
		self._cap = bit.bxor( self._cap or 0, capabilities )
	end
	---Sets the capabilities ( This overrides all capabilities, ot add or remove use CapabilitiesAdd or CapabilitiesRemove )
	---@param capabilities number
	function ENT:CapabilitiesSet( capabilities )
		self._cap = capabilities
	end

	---Returns true if the bot has said capability
	---@param capabilities number
	function ENT:CapabilitiesHas( capability )
		return bit.band(self._cap or 0, capability) ~= 0
	end
end

-- PathFind
do

	---Creates a LPathFollower using the bots data. Returns false if unable to create a path.
	---@param pos Vector
	---@param generator? function
	---@param MaxDistance? number
	---@return LPathFollower|boolean
	function ENT:PathFindTo( pos, options, generator, MaxDistance )
		local pt = self:GetPathType()
		if pt == PATHTYPE_AIN then
			local nT = self:CapabilitiesHas(CAP_MOVE_FLY) and NODE_TYPE_AIR or NODE_TYPE_GROUND
			return NodeGraph.PathFind( self:GetPos() + self:OBBCenter(), pos, nT, options, self:GetHullType(), generator )
		elseif pt == PATHTYPE_NAV then -- Not added
			return false
		elseif pt == PATHTYPE_NIKNAV then
			local w = self:OBBMaxs() - self:OBBMins()
			return NikNav.PathFind( self:GetPos() + self:OBBCenter(), pos, max(w.x, w.y) / 2, w.z, options, generator )
		end
		return false
	end

	local SysTime = SysTime
	local ASyncI = 0
	local tab = {}
	-- Calculates a path, and returns the cost or 0
	local function Tick()
		if #tab < 1 then return 0 end
		local a = table.remove( tab, 1 )
		local ent = a[1]
		local s = SysTime()
		ent._pathA = ent:PathFindTo( a[2], a[3], a[4], a[5] ) or false
		return SysTime() - s
	end

	local max_cost_pr_tick = 0.1
	local wallet = 0
	hook.Add("Think", "NikNav_ASyncThink", function()
		wallet = math.min(max_cost_pr_tick, wallet + 0.002)
		if #tab == 0 then return end
		if wallet <= 0 then return end
		for i = 1, #tab do
			if wallet <= 0 then break end
			wallet = wallet - Tick()
		end
	end)

	---Creates a LPathFollower using the bots data. Returns true if we started generating it. Result will be returned in the callback.
	---@param pos Vector
	---@param callback function
	---@param options? function
	---@param MaxDistance? number
	---@return boolean
	function ENT:PathFindToASync( pos, options, generator, MaxDistance )
		self._pathA = nil
		tab[#tab + 1] = { self, pos, options, generator, MaxDistance }
		while self._pathA == nil do -- Wait until we recive our path
			coroutine.yield()
		end
		return self._pathA
	end
	
	local function DefaultTolerance( self )
		if self._dtolo then return self._dtolo end
		local v0, v1 = self:OBBMins(), self:OBBMaxs()
		self._dtolo = max(-v0.x, -v0.y, v1.x, v1.y, 20) / 2
		return self._dtolo
	end

	---Makes the NPC use the segment
	---@param self Entity
	---@param seg table
	---@param tolerance number
	---@param face_towards number|Entity
	---@param make_body_turn= boolean		Makes the body slowly turning towards the
	---@return boolean success
	---@return boolean blocked
	local function UseSegment( self, seg, tolerance, face_towards, make_body_turn )
		if seg.move_type == CAP_MOVE_CLIMB then
			local y = self:GetAngles().y
			if seg.node then
				y = seg.node:GetYaw()
			end
			local success = self:Climb( seg.pos, y, tolerance) 
			self:WaitUntilOnGround()	-- Make sure we're on the ground before we continue
			return success, success == nil
		elseif seg.move_type == CAP_MOVE_FLY then
			local success = self:FlyToPosition( seg.pos, self:GetMoveSpeed(), tolerance )
			return success, success == nil
		elseif seg.move_type == CAP_MOVE_JUMP then
			local success = self:JumpAcrossGap( seg.pos )
			self:WaitUntilOnGround()	-- Make sure we're on the ground before we continue
			return success, success == nil
		else
			local success = self:WalkToPosition( seg.pos, tolerance, face_towards, make_body_turn )
			return success, success == nil
		end
	end

	local function angleDif( a, b )
		local a = a - b
		return abs( (a + 180) % 360 - 180 )
	end

	---Makes the NPC use the given pathfind
	---@param LPathFollower LPathFollower
	---@param options table
	---@return string result Returns: "failed", "ok", "stuck", "timeout" or "block". Where "block" is movecalls failiong.
	function ENT:MoveUsingPath( LPathFollower, options )
		if not IsValid( LPathFollower ) then return "failed" end -- Invalid path
		if self:GetMoveSpeed() <= 0 then return "failed" end -- Unable to move

		local seq, id = LPathFollower:FindClosestSeg( self:GetPos() )
		if not seq then return "failed" end -- SUnable to locate the closest segment
		options = options or {}
		local tolerance = ( options.tolerance or DefaultTolerance( self ) )
		local goal_tolerance =  options.goal_tolerance or tolerance
		local maxage = options.maxage and ( options.maxage + CurTime() )
		local face_towards = options.face_towards or nil
		local make_turn = options.make_body_turn or false
		local repath, goal, generator, maxdis
		if options.repath then -- Make sure to save the LPath options to repath, in case something invalidates it.
			repath = options.repath + CurTime()
			-- Copy the same building blocks
			goal = LPathFollower:GetEnd()
			generator = LPathFollower._generator
			maxdis = LPathFollower._MaxDistance
		end
		local dif = angleDif(seq.yaw, self:GetAngles().y)
		if dif < -20 or dif > 20 then -- Somewhat a turn
			self:OnTurn(dif, (180 + seq.yaw) % 360)
		end
		local m = #LPathFollower._segments
		while( IsValid( LPathFollower )) do
			-- Use the segment
			local success, block = UseSegment( self, seq, id >= m and goal_tolerance or tolerance, face_towards, make_turn )
			if block then -- OPne of the movecalls returned false
				return "block"
			elseif not success then
				self:HandleStuck()	-- For what I understand, this shold make the NPC "backtrack" a bit.
				return "stuck"
			elseif id < m then -- Move to next segment
				local old_seq = seq
				id = id + 1
				seq = LPathFollower._segments[id]
				if old_seq.move_type~= seq.move_type then
					if seq.move_type == CAP_MOVE_CLIMB then -- Make sure we're close at the climbing node, before running
						i = 4
						local g_pos = old_seq.pos - old_seq.forward * 15
						while self:GetPos():Distance(g_pos) > 15 and i > 0 do
							self:Approach(g_pos)
							i = i - 1
							coroutine.yield()
						end
						self:SetPos(g_pos)
					end
					self:OnNewMoveType( seq.pos, seq.move_type, old_seq.move_type )
				else -- Approach
					local dif = angleDif(seq.yaw, old_seq.yaw)
					if dif < -20 or dif > 20 then -- Somewhat a turn
						self:OnTurn(dif, (180 + seq.yaw) % 360)
					end
				end
			else
				return "ok" -- Finished
			end

			-- Timeout
			if maxage and maxage > c_time then
				return "timeout"
			end

			-- Repath option
			if repath and repath < c_time then
				repath = options.repath + c_time
				local np = self:PathFindTo( goal, generator, maxdis )
				if np then -- Failed to repath
					LPathFollower = np
					seq, id = LPathFollower:FindClosestSeg( self:GetPos() )
					t_since = CurTime()
					t_dis = nil
				end
			end
			coroutine.yield()
		end
		return "ok"
	end

	---Same as nextbot:MoveToPos, but allows jumping, climbing, pathtypes and more
	---@param pos Vector
	---@param options table
	---@return string
	function ENT:MoveToPos( pos, options )
		local lpath = self:PathFindTo( pos )
		if not lpath then return "failed" end
		return self:MoveUsingPath( lpath, options )
	end

end