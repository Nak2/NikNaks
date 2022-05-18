-- Copyright © 2022-2072, Nak, https://steamcommunity.com/id/Nak2/
-- All Rights Reserved. Not allowed to be reuploaded.
NikNaks()
-- These are "default" moves.
local abs, min, max, sqrt, AngleDifference, atan2 = math.abs, math.min, math.max, math.sqrt, math.AngleDifference, math.atan2
local pi = math.pi

local function DefaultTolerance( self )
	if self._dtolo then return self._dtolo end
	local v0, v1 = self:OBBMins(), self:OBBMaxs()
	self._dtolo = max(-v0.x, -v0.y, v1.x, v1.y, 20) / 3
	return self._dtolo
end

local function dis_2d( from, to )
	return sqrt( (from.x - to.x) ^ 2 + (from.y - to.y) ^ 2 )
end

local function yaw_2d( from, to )
	return atan2(to.y - from.y, from.x - to.x) * 180 / pi
end


-- Hull Type
do
	---Sets the NPC's HullType
	---@param HULL number
	function ENT:SetHullType( HULL )
		self._hull = HULL
	end
	---Returns the NPC's HullType
	---@return number
	function ENT:GetHullType()
		if not self._hull then
			self._hull = util.FindEntityHull( self )
			return self._hull
		end
		return self._hull
	end
end

-- Speed / Movement
do
	---Freezes the bot in place and stops the entity from "thinking"
	---@param frozen boolean
	function ENT:Freeze( frozen )
		if frozen~=false then
			self:AddFlags( FL_FROZEN )
			self._freeze = true
		else
			self:RemoveFlags( FL_FROZEN )
			self._freeze = false
		end
	end

	---Sets the movespeed.
	---@param num number
	function ENT:SetMoveSpeed( num )
		self._speed = num
		self.loco:SetDesiredSpeed( num )
	end
	---Returns the current movespeed.
	---@return number
	function ENT:GetMoveSpeed()
		if self._freeze then return 0 end
		return self._speed or self:GetDesiredSpeed()
	end

	---Sets the acceleration
	---@param num number
	function ENT:SetAcceleration( num )
		self.loco:SetAcceleration( num )
	end

	---Returns the acceleration
	---@return number
	function ENT:GetAcceleration()
		return self.loco:GetAcceleration()
	end

	---Waits until we're on the ground
	function ENT:WaitUntilOnGround()
		while not self:IsOnGround() do
			coroutine.yield()
		end
	end
	---Approach the position
	---@param pos Vector
	function ENT:Approach( pos, dontFace )
		self.loco:Approach( pos, 1 )
		if dontFace then return end
		self:FaceTowards( pos )
	end
end

-- How much the NPC likes/dislikes to jump
do
	---Sets the jump multiplier. This is how much the NPC likes/dislikes to jummp.
	---@param num number
	function ENT:SetJumpMultiplier( num )
		self._jmul = num
	end

	---Returns the jump multiplier.
	---@return number
	function ENT:GetJumpMultiplier()
		return self._jmul or 1.2
	end
end

local function angleDif( a, b )
	local a = a - b
	return abs( (a + 180) % 360 - 180 )
end

-- Face
do
	---Forces the bot face the position. Setting wait_until to false, will stop the NPC from waiting until facing the direction.
	---@param pos Vector
	---@param wait_until? boolean
	function ENT:FaceTowards( pos, wait_until )
		if not wait_until then
			self.loco:FaceTowards( pos )
		else
			local desiredy = (pos - self:GetPos()):Angle().y -- What we want to rotate to
			local aDiff = angleDif( self:GetAngles().y, desiredy )
			local t_rate = max(1, self.loco:GetMaxYawRate() / 2)
			local i = aDiff / t_rate
			while i > 0 do
				local cury = self:GetAngles().y
				i = i - 1
				if angleDif(cury, desiredy ) < t_rate then break end
				self.loco:FaceTowards( pos )
				self.loco:FaceTowards( pos )
				self.loco:FaceTowards( pos )
				self.loco:FaceTowards( pos )
				coroutine.wait(0.1)
			end
			self:SetAngles(Angle(0,desiredy,0))
			coroutine.yield()
		end
	end

	---Makes the bot face the yaw direciton. Setting wait_until to false, will stop the NPC from waiting until facing the direction.
	---@param yaw number
	---@param wait_until? boolean
	function ENT:FaceTowardsYaw( yaw, wait_until )
		self:FaceTowards( self:GetPos() + Angle(0,yaw,0):Forward() * 10, wait_until )
	end
end

-- Undoes the sequence set from jump
local function Jump( self )
	local seq = self:GetSequence()
	local cyl = self:GetCycle()
	self.loco:Jump()
	self:ResetSequence( seq )
	self:SetCycle(cyl)
end
local function JumpAcrossGap(self, landingGoal, landingForward)
	local seq = self:GetSequence()
	local cyl = self:GetCycle()
	self.loco:JumpAcrossGap(landingGoal, landingForward)
	self:ResetSequence( seq )
	self:SetCycle(cyl)
end

-- Walking
do
	function ENT:GetParameters()
		for i = 0, self:GetNumPoseParameters() - 1 do
			print(i, self:GetPoseParameterName(i))
		end
	end
	---Makes the NPC walk towards this position. Returns false if we got stuck
	---@param destination Vector
	---@param tolerance? number
	---@param face_torwards? Vector|Entity
	---@param make_body_turn? boolean -- Makes the body slowly turn towards
	---@return boolean
	function ENT:WalkToPosition( destination, tolerance, face_towards, make_body_turn )
		if self:OnWalk( destination ) == false then return end
		local dis = dis_2d(self:GetPos(), destination )
		tolerance = tolerance or 0
		if dis <= tolerance then return true end
		local t_cost, t_dir = 0
		local yaw = yaw_2d( self:GetPos(), destination)
		local isFTE = face_towards and face_towards.GetPos
		-- Make sure we don't start walking towards it side-ways
		if not face_towards and angleDif(yaw, self:GetAngles().yaw) > 50 and dis < tolerance * 2 then
			self:FaceTowards( destination )
		end
		while true do
			local p = self:GetPos()
			local aDiff = angleDif(yaw, yaw_2d( p, destination))
			if aDiff > 45 then return true end
			if not face_towards then
				self:Approach( destination )
			else
				local fPos = isFTE and face_towards:GetPos() or face_towards
				local moveDir 	= self:WorldToLocal( fPos )
				local face 		= moveDir:AngleEx( self:GetForward() )
				self:Approach( destination, true )
				self:SetPoseParameter( "move_yaw", face.yaw )
				self:SetPoseParameter( "head_pitch", face.pitch )
				self:SetPoseParameter( "head_yaw", face.yaw )
				if make_body_turn then
					self.loco:FaceTowards( fPos )
				end
			end
			if self:WhileWalk( destination ) == false then return end
			local dis = dis_2d( p, destination )
			
			if dis <= tolerance then
				return true
			elseif not t_dir or dis < t_dir then
				t_dir = dis
				t_cost = 0
			else
				t_cost = t_cost + 1
				if t_cost > 10 then -- Unable to walk this way, called this 10 times and didn't get closer.
					return false
				end
			end
			coroutine.yield()
		end
		coroutine.yield()
		return true
	end
end

-- Flying
do
	---Makes the bot fly towards a position. Will return true if successful
	---@param destination Vector
	---@param speed? number
	---@param tolerance? number
	---@param force? boolean Forces the bot to fly to the location, regardless of collisions.
	---@return boolean
	function ENT:FlyToPosition( destination, speed, tolerance, force )
		local start_pos = self:GetPos()
		local distance = start_pos:Distance( destination )
		if self:OnFly( destination, distance ) == false then return end
		local dir = ( destination - start_pos ):GetNormalized()
		local vdir = dir * speed
		tolerance = tolerance or DefaultTolerance( self )
		speed = speed or self:GetMoveSpeed()
		local grav = self.loco:GetGravity()
		self.loco:SetGravity(0)
		Jump(self) -- Tell the loco we're in the air. There might be better ways.
	
		local t_cost, t_dir = 0, 0
		local f_dis = 0
		while true do
			self.loco:SetVelocity( vdir )
			if force then -- Forces the NPC to towards the point
				self:SetPos( start_pos + dir * f_dis )
				f_dis = min(f_dis + speed / 10, distance)
			end
			local dis = self:GetPos():Distance( start_pos )
			if dis >= distance - tolerance then
				break
			elseif dis > t_dir then
				t_dir = dis
				t_cost = 0
			else
				t_cost = t_cost + 1
				if t_cost > 10 then -- Unable to fly to this, called this 10 times and didn't get closer and it failed.
					self.loco:SetGravity( grav )
					return false
				end
			end
			if self:WhileFly( dis ) == false then return end
			coroutine.yield()
		end
		self.loco:SetGravity( grav )
		if force then
			self:SetPos(destination)
		end
		return true
	end
end

-- Jumping
do
	---Returns true if the bot is within a jump.
	---@return boolean
	function ENT:IsJumping()
		return self._jump or false
	end
	---Sets the jumpheight
	---@param height number
	function ENT:SetJumpHeight( height )
		self.loco:SetJumpHeight( height )
	end
	---Returns the jumpheight
	---@return number
	function ENT:GetJumpHeight()
		return self.loco:GetJumpHeight()
	end
	---Tries to make the bot jump. Returns true if we was successful.
	---@return boolean 
	function ENT:Jump()
		if not self.loco:IsOnGround() then return false end
		if self:OnJump() == false then return end
		self._jump = true
		Jump(self)
		coroutine.wait(0.1)
		local t_cost = CurTime() + 8
		while not self.loco:IsOnGround() do
			if t_cost > CurTime() then break end
			if self:WhileJump() == false then
				self._jump = false
				return
			end
			coroutine.yield()
		end
		self._jump = false
		return true
	end
	---Tries to make the bot jump across a gab / leap forward.
	---@param landingGoal Vector
	---@param landingForward? Vector
	---@return boolean
	function ENT:JumpAcrossGap( landingGoal, landingForward )
		if not self.loco:IsOnGround() then return false end
		local pos = self:GetPos()
		landingForward = landingForward or ( landingGoal - pos ):GetNormalized()
		self:FaceTowards( landingGoal, true )
		if self:OnJumpAcrossGab( landingGoal, landingForward ) == false then return end
		self._jump = true
		if abs( pos.z - landingGoal.z ) < 150 then -- This can use the NAV jumpacrossgab
			JumpAcrossGap( self, landingGoal, landingForward )
			coroutine.wait(0.1)	
			local t_cost = CurTime() + 8
			while not self.loco:IsOnGround() do
				if t_cost > CurTime() then break end
				if self:WhileJumpAcrossGab( self:GetPos():Distance( landingGoal ) ) == false then
					self.loco:SetVelocity( vector_zero )
					self._jump = false
					return
				end
				coroutine.yield()
			end
		else	-- Nextbots isn't made for these high jumps, make our own curve
			self:FlyToPosition( landingGoal, self:GetMoveSpeed(), 20, nil, true )
		end
		self.loco:SetVelocity( vector_zero )
		self._jump = false
		return true
	end
end

-- Climbing
do
	---Returns true if the bot is climbing
	---@return boolean
	function ENT:IsClimbing()
		return self._climb or false
	end
	---Sets the climbing speed. Default is 80% MoveSpeed
	---@param num number
	function ENT:SetClimbSpeed( num )
		self._climbspeed = num
	end
	---Returns the climbing speed.
	---@return number
	function ENT:GetClimbSpeed()
		return self._climbspeed or ( self:GetMoveSpeed() * 0.8 )
	end

	---Makes the NPC climb. Returns true if we reached the distination, False if we failed.
	---@param destination Vector
	---@param yaw? number
	---@param tolerance? number
	---@return boolean
	function ENT:Climb( destination, yaw, tolerance )
		local starting_pos = self:GetPos()
		dir = ( destination - starting_pos ):GetNormalized()
		local distance = starting_pos:Distance( destination )
		if distance < tolerance then return true end -- Already there
		if not yaw then
			yaw = dir:Angle().y
		end
		self:FaceTowardsYaw( yaw, true )
		if self:OnClimb( destination, distance, dir, yaw ) == false then return end
		-- Start climbing
		do
			self._climb = true
			local grav = self.loco:GetGravity()
			self.loco:SetGravity(0)
			Jump(self) -- Tell the loco we're in the air. There might be better ways.
			local f_dis = 0
			while true do -- This won't fail, since we use SetPos and force the NPC. (We do this cause the NPC tent to get stuck flying against the wall)
				local dis = self:GetPos():Distance( starting_pos )
				if dis >= distance - tolerance or f_dis > distance then
					break
				elseif self:WhileClimb( distance - f_dis ) == false then
					self._climb = false
					self.loco:SetGravity( grav )
					self.loco:SetVelocity( vector_zero )
					return
				end
				local speed = self:GetClimbSpeed()
				local vdir = dir * speed
				self.loco:SetVelocity( vdir )
				self:SetPos( starting_pos + dir * f_dis )
				f_dis = f_dis + speed / 10
				coroutine.yield()
			end
			self.loco:SetGravity( grav )
			self.loco:SetVelocity( vector_zero )
			self:SetPos( destination ) -- Make sure we reached the point
			self._climb = false
		end
		return true
	end
end

---Returns true if the bot is climbing or jumping.
---@return boolean
function ENT:IsClimbingOrJumping()
	return self._climb or self._jump
end

---Step size
---@param height number
function ENT:SetStepHeight( num )
	self.loco:SetStepHeight( num )
end

---Get step size
---@return height number
function ENT:GetStepHeight( )
	return self.loco:GetStepHeight( )
end

-- Adds the freeze function to the nextbot.
function ENT:BehaveUpdate( fInterval )
	if not self.BehaveThread then return end
	if self._freeze then return end -- Blocks the NPC from moving.
	if ( coroutine.status( self.BehaveThread ) == "dead" ) then
		self.BehaveThread = nil
		Msg( self, " Warning: ENT:RunBehaviour() has finished executing\n" )
		return
	end
	local ok, message = coroutine.resume( self.BehaveThread )
	if ( ok == false ) then
		self.BehaveThread = nil
		ErrorNoHalt( self, " Error: ", message, "\n" )
	end
end