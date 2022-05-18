--[[
	Same as nextbot, but has build in LPathFollower support and a few features
]]
NikNaks()
AddCSLuaFile()

ENT.Base = "base_naksbot"

ENT.Spawnable = true
ENT.AdminOnly = false

ENT.PainSound = "NPC_Antlion.Pain"
ENT.IdleSound = "NPC_Antlion.Idle"
ENT.FootstepSoft = "NPC_Antlion.FootstepSoft"
ENT.FootstepHeavy = "NPC_Antlion.FootstepHeavy"

if SERVER then
	util.AddNetworkString( "base_naksbot" )
	ENT.ViewDistance = 2000

	function ENT:UpdatePath( path )
		net.Start( "base_naksbot" )
			net.WriteEntity( self )
			net.WritePath( path )
		net.Broadcast()
	end

	function ENT:Initialize()
		self:SetModel("models/AntLion.mdl")
		self:SetSkin( math.random(0, 3) )
		self:SetHullType(HULL_MEDIUM)

		self:CapabilitiesAdd( CAP_MOVE_GROUND )
		self:CapabilitiesAdd( CAP_MOVE_CLIMB )
		self:CapabilitiesAdd( CAP_MOVE_JUMP )

		self:SetMoveSpeed(360)
		self:SetAcceleration(360 * 2)
		self:SetJumpMultiplier(0.8)
		self:SetStepHeight(40)

		--self:SetCollisionBounds( ModelSize( self:GetModel() ) )
		self._idlesnd = 0

		self.loco:SetMaxYawRate(40)

		self:SetPathType( PATHTYPE_NIKNAV )
		self:AddSolidFlags( FSOLID_NOT_STANDABLE ) -- Make sure the NPC can't be 
		self:SetCollisionGroup( COLLISION_GROUP_PASSABLE_DOOR )
		self:SetSolidMask(MASK_PLAYERSOLID_BRUSHONLY)
	end

	function ENT:Think()
		local target = self:GetTarget()
		if target then
			self:SetNPCState( NPC_STATE_COMBAT )
		elseif self._alertpos then
			self:SetNPCState( NPC_STATE_ALERT )
		else
			self:SetNPCState( NPC_STATE_IDLE )
			local c = CurTime()
			if self._idlesnd < c then
				self:EmitWaitSound( self.IdleSound )
				self._idlesnd = c + 4
			end
		end
	end

	-- Attack functions
	local v1, v2 = Vector(-16,-16,-32), Vector(16,16,32)
	function ENT:PrimaryAttack( target )
		local moveDir 	= self:WorldToLocal( target:GetPos() )
		local face 		= moveDir:AngleEx( self:GetForward() )
		self:SetPoseParameter( "move_yaw", face.yaw )
		self:SetPoseParameter( "head_pitch", face.pitch )
		self:SetPoseParameter( "head_yaw", face.yaw )

		self:FaceTowards( target:GetPos() )
		self:StartActivity( ACT_RANGE_ATTACK1 )
		self:ResetSequence("attack1")
		coroutine.wait(0.6)
		local hitEntity =self:CheckMeleeTrace( target, 100, v1, v2 )
		self:EmitSound("NPC_Antlion.MeleeAttack")
		if hitEntity then
			local dmg_info = self:CalcDamage( hitEntity, 5, DMG_SLASH , dmg_force, dmg_pos, dmg_inflictor )
			self:CalculateMeleeDamageForce(dmg_info, (self:GetPos() - hitEntity:GetPos()):GetNormalized() )
			target:TakeDamageInfo( dmg_info )
		end
		coroutine.wait(0.2)
		self:SetPoseParameter( "move_yaw", 0 )
		self:SetPoseParameter( "head_pitch", 0 )
		self:SetPoseParameter( "head_yaw", 0 )
		
	end

	-- Move functions
	do
		function ENT:OnTurn( yaw_diff, new_yaw )
			if yaw_diff < -60 then
				self:StartActivity( ACT_IDLE )
				self.loco:SetVelocity( self.loco:GetVelocity() * 0.4 )
				self:ResetSequence("turn_left")
				self:FaceTowardsYaw( new_yaw, true )
			elseif yaw_diff > 60 then
				self:StartActivity( ACT_IDLE )
				self:ResetSequence("turn_right")
				self.loco:SetVelocity( self.loco:GetVelocity() * 0.4 )
				self:FaceTowardsYaw( new_yaw, true )
			elseif yaw_diff > 30 or yaw_diff < -30 then
				self:FaceTowardsYaw( new_yaw, true )		
			end
		end
		function ENT:MoveLeft( distance )
			self:ResetSequence("scuttleleft")
			local l = math.max( self:GetMoveSpeed(), 1 )
			local estimated = distance / l + CurTime()
			while estimated > CurTime() do
				self:Approach( self:GetPos() + self:GetRight() * -10, true  )
				coroutine.yield()
			end
		end
		function ENT:MoveRight( distance )
			self:ResetSequence("scuttlert")
			local l = math.max( self:GetMoveSpeed(), 1 )
			local estimated = distance / l + CurTime()
			while estimated > CurTime() do
				self:Approach( self:GetPos() + self:GetRight() * 10, true  )
				coroutine.yield()
			end
		end
		function ENT:DigDown()
			if self._dig then return end
			self:EmitSound( "NPC_Antlion.BurrowIn" )
			local len = self:SetSequence( "digin" ) / 2
			self:ResetSequenceInfo()
			self:SetCycle( 0 )
			self:SetPlaybackRate( 1 )
			self:Wait(len)
			self:DrawShadow( false )
			self:AddSolidFlags( FSOLID_NOT_SOLID )
			self:Wait(len)
		end
		function ENT:DigUp()
			self._dig = false
			local len = self:SetSequence( "digout" ) / 2
			util.ScreenShake( self:GetPos(), 0.5, 80, 1, 256 )
			self:EmitSound( "NPC_Antlion.BurrowOut" )
			self:ResetSequenceInfo()
			self:SetCycle( 0 )
			self:SetPlaybackRate( 1 )
			self:Wait(len)
			self:DrawShadow( true )
			self:RemoveSolidFlags( FSOLID_NOT_SOLID )
			self:Wait(len)
		end
		function ENT:OnWalk()
			self:StartActivity( ACT_WALK )
		end
	end

	do -- Target and Damage
		function ENT:OnInjured( info )
			self:EmitForceWaitSound( self.PainSound ) -- Will stop any other sound
			if self:HasTarget() then return end -- We don't care, got a target
			self:InterruptWait()
			local obj = info:GetAttacker()
			if IsValid( obj ) then
				self:SetTarget( obj )
			end
		end
		function ENT:OnNewTarget()
			--self:EmitWaitSound(  )
		end
	end

	-- Animations
	local idle = { "idle", "distractidle2", "distractidle3", "distractidle4"}
	function ENT:OnIdle()
		self:PlaySequenceAndWait( idle[math.random(1,4)] )
	end

	local target_options = {}
	target_options.tolerance = 30
	target_options.goal_tolerance = 80
	target_options.make_body_turn = false
	

	function ENT:RunBehaviour()
		while true do
			local follow = self._follow
			local target = self:GetTarget()  or Entity(1)
			if target then
				local path = self:PathFindToASync( target:GetPos(), target_options )
				if path then
					self:UpdatePath( path )
					--target_options.face_towards = target
					self:MoveUsingPath( path, target_options )
					if target:GetPos():Distance(self:GetPos()) <= 100 then
						self:PrimaryAttack( target )
					end
				end
			elseif follow then

			else
				self:OnIdle()
				self:MoveRight( 400 )
				self:OnIdle()
				self:MoveLeft( 400 )
				self:DigDown()
				self:DigUp()
			end
			coroutine.yield()	
		end
	end
else
	function ENT:Initialize()
		self:SetIK( true )
	end
	function ENT:PathFindTo( pos, options, generator, MaxDistance )
		local w = self:OBBMaxs() - self:OBBMins()
		return NikNav.PathFindASync( self:GetPos() + self:OBBCenter(), pos,nil, math.max(w.x, w.y) / 2, w.z, options, generator )
	end
	net.Receive("base_naksbot", function( len )
		local ent = net.ReadEntity()
		if not IsValid( ent ) then return end
		ent._path = net.ReadPath()
	end)
	function ENT:Draw()
		self:DrawModel()
		if self._path then
			self._path:DebugRender()
		else
		--	print(path)
		end
	end
end