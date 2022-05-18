
-- Wait functions with interrupt functions. Useful for damage and other things.


function ENT:Wait( num )
	self._interrupt = false
	local c = CurTime() + num
	while c > CurTime() and not self._interrupt do
		coroutine.yield()
	end
end

function ENT:InterruptWait()
	self._interrupt = true
end

function ENT:PlaySequenceAndWait( name, speed)
	local len = self:SetSequence( name )
	speed = speed or 1

	self:ResetSequenceInfo()
	self:SetCycle( 0 )
	self:SetPlaybackRate( speed )

	-- wait for it to finish
	self:Wait( len / speed )
end

function ENT:OnInjured( info )
	self:InterruptWait()
end


function ENT:GetNPCState()
	return self._state or NPC_STATE_NONE
end
function ENT:SetNPCState( state )
	self._state = state
end