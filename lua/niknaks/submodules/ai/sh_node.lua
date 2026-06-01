
local format = string.format
local NUM_HULLS = NikNaks.HULL.NUM_HULLS

NikNaks.Path.AI = NikNaks.Path.AI or {}

---Valves old AI node system
---@class AI_Node
---@field _file AI_Network
---@field _offsets table<HULL, number>
---@field _yaw number
---@field _info AI_NODE_CLIMB
---@field _lookupId integer?    -- Holds the entity-link
---@field _zone integer                 -- Will be generated when saving
---@field _links table<AI_Node, table<HULL, AI_MOVE_FLAGS>>
---@field _pos Vector
---@field _rawpos Vector
---@field _gridKey string?
---@field _type AI_NodeType
---@field _controllers AI_Controller[] -- Controllers whose volume contains this node's position
local meta = {}
meta.__index = meta
meta.MetaName = "AI Node"
NikNaks.Path.AI.NodeMeta = meta

meta.__tostring = function( self )
    return meta.MetaName
end

---Type of nodes.
---@enum AI_NodeType
NikNaks.Path.AI.NodeTypes = {
    Any = 0,
    Invalid = 1, -- Also known as "Deleted"
    Ground = 2,
    Air = 3,
    Climb = 4,
    Water = 5, -- This is not used.
}

---@enum AI_MOVE_FLAGS
NikNaks.Path.AI.MoveFlags = {
    None = 0,
    Ground = 1,
    Jump = 2,
    Fly = 4,
    Climb = 8,
}

---Also known as "info" on nodes. So far only used for climbing
---@enum AI_NODE_CLIMB
NikNaks.Path.AI.NodeClimb = {
    None = 0,
    Bottom = 1,         -- Exit point at the bottom of the climb
    On = 2,             -- Entrence point on the climb
    OffFoward = 4,      -- Exit point at the forward edge of the climb
    OffLeft = 8,        -- Exit point at the left edge of the climb
    OffRight = 16       -- Exit point at the right edge of the climb
}

---Returns the type of the node
---@return AI_NodeType
function meta:GetType()
    return self._type
end

---Sets the node type
---@param type AI_NodeType
function meta:SetType(type)
    self._type = type
end

---Sets the clumb type of the node.
---@param climbType AI_NODE_CLIMB
---@param enable boolean
function meta:SetClimbFlag(climbType, enable)
    if(enable) then
        self._info = bit.bor(self._info, climbType)
    else
        self._info = bit.band(self._info, bit.bnot(climbType))
    end
end

---Returns true if the node has the climb type.
---@param climbType AI_NODE_CLIMB
---@return boolean
function meta:HasClimbFlag(climbType)
    return bit.band(self._info, climbType) ~= 0
end

---Returns true if this climb node is accessible without climbing ability.
---@return boolean
function meta:IsWalkableClimb()
    if self._type ~= NikNaks.Path.AI.NodeTypes.Climb then return true end
    return not self:HasClimbFlag(NikNaks.Path.AI.NodeClimb.On)
end

---Returns the yaw of the node
---@return number
function meta:GetYaw()
    return self._yaw
end

---Sets the yaw of the node
---@param yaw number
function meta:SetYaw(yaw)
    self._yaw = yaw
end

---Returns the raw position of the node.
---@return Vector
function meta:GetRawPos()
    return self._rawpos
end

---Returns the position of the node.
---@return Vector
function meta:GetPos()
    return self._pos
end

local NODE_CLIMB_OFFSET = 8
local hullOFfset = {
    [NikNaks.HULL.HUMAN] = 13,
    [NikNaks.HULL.SMALL_CENTERED] = 20,
    [NikNaks.HULL.WIDE_HUMAN] = 15,
    [NikNaks.HULL.TINY] = 12,
    [NikNaks.HULL.WIDE_SHORT] = 35,
    [NikNaks.HULL.MEDIUM] = 16,
    [NikNaks.HULL.TINY_CENTERED] = 8,
    [NikNaks.HULL.LARGE] = 40,
    [NikNaks.HULL.LARGE_CENTERED] = 38,
    [NikNaks.HULL.MEDIUM_TALL] = 18,
}

---Calculates the AI position of the node
---@param hull HULL
---@return Vector
function meta:CalculatePosition(hull)
    if(self._type == NikNaks.Path.AI.NodeTypes.Climb) then
        local origin
        local shift = (hullOFfset[hull] or hullOFfset[1]) + NODE_CLIMB_OFFSET
        local offsetDir = Vector(math.cos(math.rad(self._yaw)), math.sin(math.rad(self._yaw)), 0)
        if(self:HasClimbFlag(NikNaks.Path.AI.NodeClimb.OffFoward)) then
            origin = self:GetPos() + (shift * offsetDir)
        elseif(self:HasClimbFlag(NikNaks.Path.AI.NodeClimb.OffLeft)) then
            local leftDir = offsetDir:Cross(vector_up)
            origin = self:GetPos() - (2 * shift * leftDir) - (shift * offsetDir)
        elseif(self:HasClimbFlag(NikNaks.Path.AI.NodeClimb.OffRight)) then
            local leftDir = offsetDir:Cross(vector_up)
            origin = self:GetPos() + (2 * shift * leftDir) - (shift * offsetDir)
        else
            origin = self:GetPos() - (shift * offsetDir)
        end
        return origin -- This is in the source code but seems unused. Code will never hit this.
    elseif(self._type == NikNaks.Path.AI.NodeTypes.Ground) then
        local v = self:GetPos()
        return Vector(v.x, v.y, v.z + (self._offsets[hull] or 0))
    else
        return self:GetPos()
    end
end

---Returns the entitylink of the node, if it has one.
---@return AI_LookupLink?
function meta:GetLookupLink()
    if not self._lookupId or self._lookupId < 0 then return end
    return NikNaks.Path.AI.GetLookupTable()[self._lookupId]
end

---Returns dynamicLinks of the node, if it has an entity link.
---@return AI_DynamicLink[]?
function meta:LocateDynamicLinks()
    local entityLink = self:GetLookupLink()
    if not entityLink then return end
    return entityLink.dynamicLinks
end

---Sets the entitylink id
---@param nodeIndex integer?
function meta:SetLookupLinkIndex(nodeIndex)
    -- Guard against no-op
    if nodeIndex == self._lookupId then return end

    -- Clear our own old entry first
    if self._lookupId ~= nil then
        self._file._entityLookup[self._lookupId] = nil
    end

    if nodeIndex ~= nil then
        -- Evict any node currently holding this index
        local occupant = self._file._entityLookup[nodeIndex]
        if occupant and occupant ~= self then
            occupant._lookupId = nil  -- bypass recursion, just clear the field
        end
        self._file._entityLookup[nodeIndex] = self
    end

    self._lookupId = nodeIndex
end

local GRID_SIZE = 1000

local function gridKey(pos)
    local gx = math.floor(pos.x / GRID_SIZE)
    local gy = math.floor(pos.y / GRID_SIZE)
    return gx .. "," .. gy
end

function meta:SetPos(vec)
    local graph = self._file._graph  -- fix: was bare `file`

    -- Clear old grid entry (fix: was grid[x][y][y])
    if self._gridKey then
        local cell = graph[self._gridKey]
        if cell then
            local n = #cell
            for i = 1, n do
                if cell[i] == self then
                    cell[i] = cell[n]  -- swap-remove: O(1) vs O(n)
                    cell[n] = nil
                    break
                end
            end
        end
    end

    self._rawpos = vec

    if self._type == NikNaks.Path.AI.NodeTypes.Ground then
        local trace = util.TraceLine({
            start  = self._rawpos + Vector(0, 0, 50),
            endpos = self._rawpos - Vector(0, 0, 128),
            mask   = MASK_SOLID_BRUSHONLY
        })
        self._pos = (trace.Hit and not NikNaks.CurrentMap:IsOutsideMap(trace.HitPos))
            and trace.HitPos
            or self._rawpos
        self:ComputeHullOffsets()
    else
        self._pos = self._rawpos
    end

    -- Cache controllers whose volume contains this node's position
    local ctrlList = NikNaks.Path.AI.GetControllers()
    if ctrlList[1] then
        local p   = self._pos
        local hit = {}
        for _, ctrl in ipairs(ctrlList) do
            if not ctrl.origin then continue end
            local o   = ctrl.origin
            local wx1 = o.x + ctrl.mins.x;  local wx2 = o.x + ctrl.maxs.x
            local wy1 = o.y + ctrl.mins.y;  local wy2 = o.y + ctrl.maxs.y
            local wz1 = o.z + ctrl.mins.z;  local wz2 = o.z + ctrl.maxs.z
            if p.x >= wx1 and p.x <= wx2 and
               p.y >= wy1 and p.y <= wy2 and
               p.z >= wz1 and p.z <= wz2 then
                hit[#hit + 1] = ctrl
            end
        end
        self._controllers = hit
    else
        self._controllers = {}
    end

    -- Insert into new grid cell
    local key = gridKey(self._pos)
    self._gridKey = key  -- cache on node for fast removal next time
    local cell = graph[key]
    if not cell then
        cell = {}
        graph[key] = cell
    end
    cell[#cell + 1] = self
end

---A table of entity links, which link entities and dynamiclinks to nodes.
---@return table<AI_Node, table<HULL, AI_MOVE_FLAGS>>
function meta:GetLinks()
    return self._links
end

---Returns true if the two nodes are linked
---@param node AI_Node
---@return boolean
function meta:HasLink(node)
    return self._links[node] ~= nil
end

---Returns the moves between this node and the other node.
---@param node AI_Node
---@param hull HULL?
---@return AI_MOVE_FLAGS
function meta:GetLinkMoves(node, hull)
    local entry = self._links[node]
    if not entry then return 0 end
    if not hull then
        local moves = 0
        for h = 0, NUM_HULLS - 1 do
            moves = bit.bor(moves, entry[h] or 0)
        end
        return moves
    end

    return entry[hull] or 0
end

---Returns true if the node has the link move
---@param node AI_Node
---@param hull HULL?
---@param moveType AI_MOVE_FLAGS
---@return boolean
function meta:HasLinkMoves(node, hull, moveType)
    return bit.band(self:GetLinkMoves(node, hull), moveType) ~= 0
end

---Removes the link between this node and another node.
---@param node AI_Node
function meta:RemoveLink(node)
    self._links[node] = nil
    node._links[self] = nil
end

local function clearIfEmpty(links, a)
    local entry = links[a]
    if not entry then return end
    for h = 0, NUM_HULLS - 1 do
        if (entry[h] or 0) ~= 0 then return end
    end
    links[a] = nil
end

---Sets the moves between this node and another node.
---@param node AI_Node
---@param hull HULL? -- Nil means all hulls
---@param move AI_MOVE_FLAGS
---@param enable boolean
function meta:SetLinkMove(node, hull, move, enable)
    if not self._links[node] then self._links[node] = {} end
    if not node._links[self] then node._links[self] = {} end

    local op = enable
        and function(cur) return bit.bor(cur, move) end
        or  function(cur) return bit.band(cur, bit.bnot(move)) end

    local hullMin = hull or 0
    local hullMax = hull or (NUM_HULLS - 1)

    for h = hullMin, hullMax do
        self._links[node][h] = op(self._links[node][h] or 0)
        node._links[self][h] = op(node._links[self][h] or 0)
    end

    if not enable then
        clearIfEmpty(self._links, node)
        clearIfEmpty(node._links, self)
    end
end

---Directly sets the move flags for a specific hull between two nodes, bypassing bitwise ops.
---Faster than SetLinkMove when you know the exact value to write.
---@param node AI_Node
---@param hull HULL
---@param move AI_MOVE_FLAGS
function meta:SetLinkMoveDirect(node, hull, move)
    if not self._links[node] then self._links[node] = {} end
    if not node._links[self] then node._links[self] = {} end
    self._links[node][hull] = move
    node._links[self][hull] = move
end

---Returns the hint type of this node, if it has an entity link.
---@return AI_InfoNodeType
function meta:GetHintType()
    local link = self:GetLookupLink()
    if not link then return NikNaks.Path.AI.HintTypes.None end
    local NONE = NikNaks.Path.AI.HintTypes.None
    for _, ent in ipairs(link.entities) do
        local hinttype = ent.hinttype
        if hinttype and hinttype ~= NONE then return hinttype end
    end
    return NONE
end


-- Safe drop distances per hull (in units) based on Source NPC values
local HULL_SAFE_DROP = {
    [NikNaks.HULL.HUMAN]          = 150,
    [NikNaks.HULL.SMALL_CENTERED] = 100,
    [NikNaks.HULL.WIDE_HUMAN]     = 150,
    [NikNaks.HULL.TINY]           = 64,
    [NikNaks.HULL.WIDE_SHORT]     = 100,
    [NikNaks.HULL.MEDIUM]         = 128,
    [NikNaks.HULL.TINY_CENTERED]  = 64,
    [NikNaks.HULL.LARGE]          = 200,
    [NikNaks.HULL.LARGE_CENTERED] = 200,
    [NikNaks.HULL.MEDIUM_TALL]    = 150,
}

local offset = 5
local HULL_MINS = {
    [NikNaks.HULL.HUMAN]          = Vector(-16 - offset, -16 - offset, 0),
    [NikNaks.HULL.SMALL_CENTERED] = Vector(-12 - offset, -12 - offset, -12),
    [NikNaks.HULL.WIDE_HUMAN]     = Vector(-24 - offset, -24 - offset, 0),
    [NikNaks.HULL.TINY]           = Vector(-8 - offset,  -8 - offset,  0),
    [NikNaks.HULL.WIDE_SHORT]     = Vector(-36 - offset, -36 - offset, 0),
    [NikNaks.HULL.MEDIUM]         = Vector(-16 - offset, -16 - offset, 0),
    [NikNaks.HULL.TINY_CENTERED]  = Vector(-8 - offset,  -8 - offset,  -8),
    [NikNaks.HULL.LARGE]          = Vector(-32 - offset, -32 - offset, 0),
    [NikNaks.HULL.LARGE_CENTERED] = Vector(-32 - offset, -32 - offset, -32),
    [NikNaks.HULL.MEDIUM_TALL]    = Vector(-16 - offset, -16 - offset, 0),
}

local HULL_MAXS = {
    [NikNaks.HULL.HUMAN]          = Vector(16 + offset,  16 + offset,  72),
    [NikNaks.HULL.SMALL_CENTERED] = Vector(12 + offset,  12 + offset,  12),
    [NikNaks.HULL.WIDE_HUMAN]     = Vector(24 + offset,  24 + offset,  72),
    [NikNaks.HULL.TINY]           = Vector(8 + offset,   8 + offset,   16),
    [NikNaks.HULL.WIDE_SHORT]     = Vector(36 + offset,  36 + offset,  36),
    [NikNaks.HULL.MEDIUM]         = Vector(16 + offset,  16 + offset,  36),
    [NikNaks.HULL.TINY_CENTERED]  = Vector(8 + offset,   8 + offset,   8),
    [NikNaks.HULL.LARGE]          = Vector(32 + offset,  32 + offset,  80),
    [NikNaks.HULL.LARGE_CENTERED] = Vector(32 + offset,  32 + offset,  32),
    [NikNaks.HULL.MEDIUM_TALL]    = Vector(16 + offset,  16 + offset,  60),
}

-- Flat (pancake) hulls for offset calculation.
-- SDK InitGroundNodePosition: set maxs.z = mins.z so the disc can't snag on ceilings.
local HULL_FLAT_MINS = {}
local HULL_FLAT_MAXS = {}
for i = 0, NikNaks.HULL.NUM_HULLS - 1 do
    local mn = HULL_MINS[i]; local mx = HULL_MAXS[i]
    if mn and mx then
        HULL_FLAT_MINS[i] = Vector(mn.x, mn.y, mn.z)
        HULL_FLAT_MAXS[i] = Vector(mx.x, mx.y, mn.z)  -- top = bottom = flat disc
    end
end

local _offTr = { start = Vector(), endpos = Vector(), mins = nil, maxs = nil, mask = MASK_NPCSOLID_BRUSHONLY }

---Computes per-hull vertical offsets for this ground node.
---Mirrors SDK CAI_NetworkBuilder::InitGroundNodePosition (ai_networkmanager.cpp:2524).
---Stores in node._offsets[hull]: added to node._pos.z to get the hull's actual
---standing Z (used by CalculatePosition). No-op for air/climb nodes.
function meta:ComputeHullOffsets()
    if self._type ~= NikNaks.Path.AI.NodeTypes.Ground then return end
    local ox = self._pos.x; local oy = self._pos.y; local oz = self._pos.z
    for hull = 0, NikNaks.HULL.NUM_HULLS - 1 do
        local mins = HULL_FLAT_MINS[hull]; local maxs = HULL_FLAT_MAXS[hull]
        if not mins or not maxs then self._offsets[hull] = 0; continue end
        -- Raise start so disc bottom sits exactly at the node origin (+0.1 epsilon)
        local startZ = oz - mins.z + 0.1
        _offTr.start.x  = ox; _offTr.start.y  = oy; _offTr.start.z  = startZ
        _offTr.endpos.x = ox; _offTr.endpos.y = oy; _offTr.endpos.z = startZ - 384
        _offTr.mins = mins; _offTr.maxs = maxs
        local tr = util.TraceHull(_offTr)
        self._offsets[hull] = not tr.startsolid
            and (tr.HitPos.z - oz + 0.1)
            or  (-mins.z + 0.1)  -- fallback: embedded in solid
    end
end

-- SDK constants (ai_moveprobe.cpp)
local STEP_SIZE    = 16      -- LOCAL_STEP_SIZE: distance per step iteration
local STEP_EPSILON = 0.0625  -- MOVE_HEIGHT_EPSILON: raise above ground to avoid embedding

-- Per-hull step heights based on typical NPC values (SDK StepHeight())
local HULL_STEP_HEIGHT = {
    [NikNaks.HULL.HUMAN]          = 18,
    [NikNaks.HULL.SMALL_CENTERED] = 16,
    [NikNaks.HULL.WIDE_HUMAN]     = 18,
    [NikNaks.HULL.TINY]           = 6,
    [NikNaks.HULL.WIDE_SHORT]     = 16,
    [NikNaks.HULL.MEDIUM]         = 16,
    [NikNaks.HULL.TINY_CENTERED]  = 6,
    [NikNaks.HULL.LARGE]          = 22,
    [NikNaks.HULL.LARGE_CENTERED] = 0,  -- helicopters/gunships/striders: air nodes only
    [NikNaks.HULL.MEDIUM_TALL]    = 18,
}
local STEP_DOWN_MULT = 2  -- GetStepDownMultiplier(): allows stepping down ramps/slopes

-- Persistent trace tables — reused every call to avoid per-call allocation.
local _slFwd     = { start = Vector(), endpos = Vector(), mins = nil, maxs = nil, mask = MASK_NPCSOLID_BRUSHONLY }
local _slStepUp  = { start = Vector(), endpos = Vector(), mins = nil, maxs = nil, mask = MASK_NPCSOLID_BRUSHONLY }
local _slStepFd  = { start = Vector(), endpos = Vector(), mins = nil, maxs = nil, mask = MASK_NPCSOLID_BRUSHONLY }
local _slDown    = { start = Vector(), endpos = Vector(), mins = nil, maxs = nil, mask = MASK_NPCSOLID_BRUSHONLY }
local _slAir     = { start = Vector(), endpos = Vector(), mins = nil, maxs = nil, mask = MASK_NPCSOLID_BRUSHONLY }
local _slJumpLOS = { start = Vector(), endpos = Vector(),                         mask = MASK_SOLID_BRUSHONLY   }

-- Mirrors SDK CheckStep (ai_moveprobe.cpp).
-- Advances one step in direction (dx,dy). Attempts step-up if blocked, then drops to ground.
-- Returns (x, y, z) on success, nil on failure.
local function checkStep(cx, cy, cz, dx, dy, stepSize, stepH, mins, maxs)
    local eps = STEP_EPSILON
    local nx  = cx + dx * stepSize
    local ny  = cy + dy * stepSize

    -- Forward trace at +epsilon height (2D sweep, Z held constant)
    _slFwd.start.x  = cx; _slFwd.start.y  = cy; _slFwd.start.z  = cz + eps
    _slFwd.endpos.x = nx; _slFwd.endpos.y = ny; _slFwd.endpos.z = cz + eps
    _slFwd.mins = mins; _slFwd.maxs = maxs
    local fwd = util.TraceHull(_slFwd)
    if fwd.startsolid then return nil end

    local landX, landY, landZ

    if fwd.Fraction < 1.0 then
        -- Blocked: trace up from the obstruction, then retry forward from raised height
        local bx = fwd.HitPos.x; local by = fwd.HitPos.y

        _slStepUp.start.x  = bx; _slStepUp.start.y  = by; _slStepUp.start.z  = cz + eps
        _slStepUp.endpos.x = bx; _slStepUp.endpos.y = by; _slStepUp.endpos.z = cz + eps + stepH
        _slStepUp.mins = mins; _slStepUp.maxs = maxs
        local up      = util.TraceHull(_slStepUp)
        local raisedZ = up.HitPos.z

        _slStepFd.start.x  = bx; _slStepFd.start.y  = by; _slStepFd.start.z  = raisedZ
        _slStepFd.endpos.x = nx; _slStepFd.endpos.y = ny; _slStepFd.endpos.z = raisedZ
        _slStepFd.mins = mins; _slStepFd.maxs = maxs
        local sf = util.TraceHull(_slStepFd)
        if sf.startsolid or sf.Fraction <= 0.01 then return nil end

        landX = sf.HitPos.x; landY = sf.HitPos.y; landZ = raisedZ
    else
        landX = nx; landY = ny; landZ = cz + eps
    end

    -- Drop to find ground (max = stepH * STEP_DOWN_MULT below the step's start Z)
    _slDown.start.x  = landX; _slDown.start.y  = landY; _slDown.start.z  = landZ
    _slDown.endpos.x = landX; _slDown.endpos.y = landY; _slDown.endpos.z = cz - stepH * STEP_DOWN_MULT - eps
    _slDown.mins = mins; _slDown.maxs = maxs
    local down = util.TraceHull(_slDown)
    if down.Fraction == 1.0 then return nil end  -- no ground below

    return landX, landY, down.HitPos.z + eps
end

-- Mirrors SDK TestGroundMove (ai_moveprobe.cpp): iterative step simulation.
-- Returns true if the hull can walk from srcPos to destPos.
local function testGroundMove(srcPos, destPos, mins, maxs, stepH)
    local sx = srcPos.x; local sy = srcPos.y; local sz = srcPos.z
    local ex = destPos.x; local ey = destPos.y; local ez = destPos.z

    local dx    = ex - sx; local dy = ey - sy
    local dist2D = math.sqrt(dx*dx + dy*dy)
    if dist2D < 0.001 then
        return math.abs(ez - sz) <= math.max(maxs.z * 0.5, stepH + 0.1)
    end
    local inv = 1.0 / dist2D
    dx = dx * inv; dy = dy * inv

    local cx = sx; local cy = sy; local cz = sz
    local walked = 0

    while walked < dist2D do
        local ss      = math.min(STEP_SIZE, dist2D - walked)
        local nx, ny, nz = checkStep(cx, cy, cz, dx, dy, ss, stepH, mins, maxs)
        if not nx then return false end
        cx = nx; cy = ny; cz = nz
        walked = walked + ss
    end

    -- SDK final check: verify we arrived near the target Z, not on a ledge above/below
    return math.abs(cz - ez) <= math.max(maxs.z * 0.5, stepH + 0.1)
end

---@class AI_SmartLinkResult
---@field hull HULL
---@field move AI_MOVE_FLAGS

---Calculates what links would be created between two positions without applying them.
---Mirrors SDK CAI_NetworkBuilder::ComputeConnection (ai_networkmanager.cpp).
---@param posA Vector
---@param posB Vector
---@param isAir boolean?  -- true if BOTH nodes are air nodes
---@return AI_SmartLinkResult[]
function NikNaks.Path.AI.CalculateSmartLink(posA, posB, isAir)
    local results  = {}
    local NUM      = NikNaks.HULL.NUM_HULLS - 1
    local FLY      = NikNaks.Path.AI.MoveFlags.Fly
    local GROUND   = NikNaks.Path.AI.MoveFlags.Ground
    local JUMP     = NikNaks.Path.AI.MoveFlags.Jump

    if isAir then
        -- SDK: air→air only, direct clearance trace per hull, no ground simulation
        for hull = 0, NUM do
            local mins = HULL_MINS[hull]; local maxs = HULL_MAXS[hull]
            if not mins or not maxs then continue end
            _slAir.start.x  = posA.x; _slAir.start.y  = posA.y; _slAir.start.z  = posA.z
            _slAir.endpos.x = posB.x; _slAir.endpos.y = posB.y; _slAir.endpos.z = posB.z
            _slAir.mins = mins; _slAir.maxs = maxs
            local tr = util.TraceHull(_slAir)
            if not tr.startsolid and tr.Fraction == 1.0 then
                results[#results + 1] = { hull = hull, move = FLY }
            end
        end
        return results
    end

    -- Ground pass: find every hull that can walk the path
    local groundHulls = {}
    local anyGround   = false
    for hull = 0, NUM do
        local mins = HULL_MINS[hull]; local maxs = HULL_MAXS[hull]
        if not mins or not maxs then continue end
        local stepH = HULL_STEP_HEIGHT[hull] or 18
        if testGroundMove(posA, posB, mins, maxs, stepH) then
            groundHulls[hull] = true
            anyGround = true
        end
    end

    if anyGround then
        -- At least one hull walks: only emit Ground results, never Jump.
        -- SDK: jump is only tried when ground walk fails; here we extend that to
        -- the whole pair — if the path is walkable at all, jump is not needed.
        for hull, _ in pairs(groundHulls) do
            results[#results + 1] = { hull = hull, move = GROUND }
        end
    else
        -- No hull can walk: try Jump for each hull independently.
        -- SDK approximation: height within NPC range AND path is clear.
        local heightDiff = posA.z - posB.z  -- positive = dropping A→B
        local peakZ      = math.max(posA.z, posB.z) + 48
        local jumpUp     = 200  -- approximate max upward jump for most NPCs

        -- LOS from slightly above ground: fast single check that rejects jumps
        -- through walls before doing the more expensive per-hull arc traces.
        _slJumpLOS.start.x  = posA.x; _slJumpLOS.start.y  = posA.y; _slJumpLOS.start.z  = posA.z + 32
        _slJumpLOS.endpos.x = posB.x; _slJumpLOS.endpos.y = posB.y; _slJumpLOS.endpos.z = posB.z + 32
        if not util.TraceLine(_slJumpLOS).Hit then
            for hull = 0, NUM do
                local mins = HULL_MINS[hull]; local maxs = HULL_MAXS[hull]
                if not mins or not maxs then continue end
                local drop = HULL_SAFE_DROP[hull] or 150
                if heightDiff < -jumpUp or heightDiff > drop then continue end
                _slAir.start.x  = posA.x; _slAir.start.y  = posA.y; _slAir.start.z  = peakZ
                _slAir.endpos.x = posB.x; _slAir.endpos.y = posB.y; _slAir.endpos.z = peakZ
                _slAir.mins = mins; _slAir.maxs = maxs
                local arc = util.TraceHull(_slAir)
                if not arc.startsolid and arc.Fraction == 1.0 then
                    results[#results + 1] = { hull = hull, move = JUMP }
                end
            end
        end
    end

    return results
end

---Automatically creates smart links between two nodes.
---@param other AI_Node
function meta:SmartLink(other)
    -- SDK (ai_networkmanager.cpp ComputeConnection): fly links only form when BOTH nodes are air.
    local isAir = self._type == NikNaks.Path.AI.NodeTypes.Air
        and other._type == NikNaks.Path.AI.NodeTypes.Air

    local results = NikNaks.Path.AI.CalculateSmartLink(self:GetPos(), other:GetPos(), isAir)
    for _, r in ipairs(results) do
        self:SetLinkMoveDirect(other, r.hull, r.move)
    end
end
