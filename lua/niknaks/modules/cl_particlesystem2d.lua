
---@class 2DParticleEmiiter
local meta = {}
NikNaks.__metatables["2DParticleEmiiter"] = meta

local CurTime = CurTime

---@class 2DParticle
local meta_2dpart = {}

---Creates a 2D particle emiiter
---@param position2D Vector
---@return 2DParticleEmiiter
function NikNaks.ParticleEmitter2D( position2D )
	local t = {}
	t.particles = {}
	t.origin = position2D or Vector(ScrW() / 2, ScrH() / 2, 0)
	t.draw = true
	t.collision = false
	t.collisionTab = {}
	return t
end

function meta:SetNoDraw( noDraw )
	self.draw = not noDraw
end

function meta:GetPos()
	return self.origin
end

function meta:SetPos( position2D )
	self.origin = position2D
end

function meta:SetCollision( bCollision )
	self.collision = bCollision
end

function meta:AddCollisionPanel( panel )
	collisionTab[#collisionTab + 1] = panel
end

function meta:SetCollisionBounds( position2DMin, position2DMax )
	self.position2DMin = self.position2DMin or Vector(0,0,0)
	self.position2DMax = self.position2DMax or Vector(ScrW(), ScrH(),0)
end

---Delete particles
function meta:Finish()
end

function meta:GetNumActiveParticles()
	return #self.particles
end

NikNaks.AccessorFuncEx( meta_2dpart, "_rotate", "Roll", FORCE_NUMBER )
NikNaks.AccessorFuncEx( meta_2dpart, "_ssize", "StartSize", FORCE_NUMBER )
NikNaks.AccessorFuncEx( meta_2dpart, "_esize", "EndSize", FORCE_NUMBER )
NikNaks.AccessorFuncEx( meta_2dpart, "_grav", "Gravity", FORCE_NUMBER )
NikNaks.AccessorFuncEx( meta_2dpart, "_dietime", "DieTime", FORCE_NUMBER )
NikNaks.AccessorFuncEx( meta_2dpart, "_origin", "Pos", FORCE_VECTOR )
NikNaks.AccessorFuncEx( meta_2dpart, "_material", "Material" )
NikNaks.AccessorFuncEx( meta_2dpart, "_color", "Color", FORCE_COLOR )
NikNaks.AccessorFuncEx( meta_2dpart, "_vel", "Velocity", FORCE_VECTOR )
NikNaks.AccessorFuncEx( meta_2dpart, "_rotateVel", "RollVelocity", FORCE_NUMBER )
-- Sets the think function to call
function meta_2dpart:SetThinkFunction( thinkFunc )
	self._thinkFunc = thinkFunc
end
-- Sets the next think function call
function meta_2dpart:SetNextThink( num )
	self._nextThink = num
end
-- Gets called when the particle is about to be removed.
function meta_2dpart:OnRemove( removeFunc )
	self._onRemove = removeFunc
end
-- Gets called if collision is on and it collides with something.
function meta_2dpart:OnCollision( onCollideFunc )
	self._onCollision = onCollideFunc
end

-- Returns how many seconds the particle have been alive for.
function meta_2dpart:GetLifeTime()
	return CurTime() - self._life
end

-- Sets the anumt of seconds the particle have been alive for.
function meta_2dpart:SetLifeTime( num )
	self._life = CurTime() - num
end

-- Invalidates the particle
function meta_2dpart:Kill()
	self._life = 0
	self._dietime = 0
end

local defaultMat = Material("__err")
function meta:Add( material, position2D )
	local t = {}
	t._material = material or defaultMat
	t._origin = position2D + self.origin
	t._starttime = 0
	t._dietime = 3
	t._grav = 0
	t._ssize = 1
	t._esize = 3
	t._rotate = 0
	t._rotateVel = 0
	t._life = CurTime()
	t._vel = Vector(0,0,0)
	setmetatable(t, meta_2dpart)
	self.particles[#self.particles + 1] = t
	return t
end

-- Local Part functions

-- Returns the particles life between 0-1
local function particleTimeFloat( part )
	return part:GetLifeTime() / part._dietime
end

-- Returns false if the particle is invalid and should be removed
local function particleValid( part )
	if not part then return false end
	local life = part:GetLifeTime()
	if life > part._dietime then return false end
	return true
end

local COL_TOP		= 0
local COL_BOTTOM	= 1
local COL_LEFT		= 2
local COL_RIGHT		= 3
local COL_CUSTOM	= 3

local function isOutside( x, y, pos, pos2)
	if x < pos.x then
		return COL_LEFT
	elseif x > pos2.x
		return COL_RIGHT
	elseif y < pos.y then
		return COL_TOP
	elseif y > pos2.y then
		return COL_BOTTOM
	end
end

local Lerp = Lerp
local function particelTick( part, parent, timeFloat )
	local timeF = timeFloat or part:particleTimeFloat()
	if self._grav ~= 0 then
		self._vel.y = self._vel.y + self._grav
	end
	-- Update size
	self._size = Lerp(timeF, self._ssize, self._esize)
	self._roll = (self._roll + self._rotateVel) % 360
	-- Update Pos
	local x = self._origin.x + self._vel.x
	local y = self._origin.y + self._vel.y
	-- Collision
	if parent.collision then
		-- Check CBounds
		if parent.position2DMin and parent.position2DMax then
			local colData = isOutside(x, y, parent.position2DMin, parent.position2DMax) 
			if colData then
				
			end
		end
	end
	
end