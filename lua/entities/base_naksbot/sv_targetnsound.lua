local TraceHull = util.TraceHull
-- Target
function ENT:SetTarget( ent )
	if IsValid( ent ) then
		self._target = ent
		self:OnNewTarget( ent )
	else
		self:OnLoseTarget( self._target )
		self._target = nil
	end
end

function ENT:GetTarget()
	return self._target 
end

function ENT:HasTarget()
	return IsValid( self._target ) or false
end

function ENT:OnNewTarget( target )
end
function ENT:OnLoseTarget( target )
end

-- Soudns
function ENT:EmitWaitSound( soundName, ...)
	if self._sspam and self._sspam >= CurTime() then return false end
	if not isstring( soundName ) then
		soundName = soundName[math.random(1, #soundName)]
	end
	self._sspam = SoundDuration( soundName ) + CurTime()
	self._ssnd = soundName
	self:EmitSound( soundName, ... )
end
function ENT:EmitForceWaitSound( soundName, ...)
	if self._sspam and self._sspam >= CurTime() then
		if self._ssnd == soundName then
			return false
		else
			self:StopSound( self._ssnd )
		end
	end
	if not isstring( soundName ) then
		soundName = soundName[math.random(1, #soundName)]
	end
	self._sspam = SoundDuration( soundName ) + CurTime()
	self:EmitSound( soundName, ... )
end

-- Damage, traces and attacks
function ENT:CheckHullTrace( goal, vMin, vMax, mask, collisiongroup )
	if not vMin then 
		vMin = self:OBBMins()
		vMin.z = 1
	end
	if not vMax then vMax = self:OBBMaxs() end

	return TraceHull({
		start = (self:GetPos() + self:OBBCenter()) + Vector(0,0,5),
		endpos = goal,
		filter = self,
		mins = vMin,
		maxs = vMax,
		mask = mask or MASK_SOLID,
		collisiongroup = collisiongroup or COLLISION_GROUP_PROJECTILE
	})
end

function ENT:CheckMeleeTrace( target, distance, vMin, vMax )
	if target and IsValid(target) then
		local t = self:CheckHullTrace( target:GetPos() + target:OBBCenter(), vMin, vMax )
		
		if not t or t.Entity ~= target then return false end -- Didn't hit the entity
		if distance and t.HitPos:Distance( t.StartPos ) > distance then return false end
		return target
	else
		local p = (self:EyePos() or self:GetPos()) + self:GetAngles() * distance
		local t = self:CheckHullTrace( p, vMin, vMax )
		if not t or not t.Hit then return false end
		local tE = t.Entity and IsValid( t.Entity )
		if not tE then return false end
		return tE
	end
end

function ENT:CalcDamage( target, dmg, dmg_type, dmg_force, dmg_pos, dmg_inflictor )
	local dmg_info = DamageInfo()
	dmg_info:SetAttacker( self )
	dmg_info:SetDamage( dmg )
	dmg_info:SetDamageType( dmg_type )
	if dmg_force then
		dmg_info:SetDamageForce( dmg_force )
	end
	dmg_info:SetReportedPosition( self:EyePos() or self:GetPos( ))
	if dmg_pos then
		dmg_info:SetDamagePosition( dmg_info )
	end
	if dmg_infict then
		dmg_info:SetInflictor( dmg_inflictor )
	end
	return dmg_info
end

local BlastDamageInfo = util.BlastDamageInfo
function ENT:DoBlastDamage( dmg_info, range )
	BlastDamageInfo( dmg_info:GetDamagePosition(), position, range )
end

function ENT:CalculateMeleeDamageForce( info, meleeDir )
	local fScale = info:GetDamage() * 75 * 4
	info:SetDamageForce( meleeDir * fScale )
end