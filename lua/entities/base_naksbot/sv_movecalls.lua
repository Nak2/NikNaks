NikNaks()
local abs = math.abs
--[[
	These functions allows you to tell the pathfinder what they're allowed to do.
	Note: Overriding the generator, will not call these functions.

	In these functions you return a cost. Returning a number allows you to override the cost.
	-1 = Now allowed to move this way
]]

function ENT:CanJump( from, to, current_cost )
end

function ENT:CanClimb( from, to, current_cost )
end

function ENT:CanFly( from, to, current_cost )
end

function ENT:CanWalk( from, to, current_cost )
end


--[[
	These functions are designed to be overriden for animations and other things.
	Returning false in any of these, will caluse the pathfinder to stop and return "block".
]]

---Gets called when the NPC is taking somewhat of a sharp turn. [-20, 20]
---@param dot number
function ENT:OnTurn( yaw_diff, new_yaw )
	if yaw_diff < -90 or yaw_diff > 90 then
		self.loco:SetVelocity( vector_zero )
	elseif yaw_diff < -90 or yaw_diff > 90 then
		local f = -0.007 * abs( yaw_diff ) + 1
		self.loco:SetVelocity(self.loco:GetVelocity() * f)
	end
end

---Gets called when the NPC is about to walk towards a point. Return false to block.
---@param destination Vector
function ENT:OnWalk( destination, distance )
end

---Gets called when the NPC is about to jump across a gab. Return false to block.
---@param landingGoal Vector
---@param landingForward Vector
function ENT:OnJumpAcrossGab( landingGoal, landingForward )
end

---Gcalled when the NPC is about to jump. Return false to block.
function ENT:OnJump( )
end

---Gets called when the NPC is flying to a point
---@param destination Vector
---@param distance number
function ENT:OnFly( destination, distance )
end

---called when the NPC is about to climb. Return false to block.
---@param destination Vector
---@param distance number
---@param dir Vector
---@param yaw number
function ENT:OnClimb( destination, distance, dir, yaw )
end

---Gets called when the NPC is switching to another move-type.
---@param destination Vector
---@param MOVE_TYPE number
function ENT:OnNewMoveType( destination, MOVE_TYPE, OLD_MOVE_TYPE )
end
					

---Gets called while the NPC is walking. Returning false will stop the NPC.
---@param distance number
function ENT:WhileWalk( distance )
end

---Gets called while the NPC is jumping across a gab. Returning false will stop the NPC.
---@param distance number
function ENT:WhileJumpAcrossGab( distance )
end

---Gets called while the bot is jumping, until it lands on the ground.
function ENT:WhileJump()
end

---Gets called while the NPC is flying
---@param distance number
function ENT:WhileFly( distance )
end

---Gets called while the NPC is climbing. Returning false will stop the NPC.
---@param distance number
function ENT:WhileClimb( distance )
end

function ENT:OnIdle()
end