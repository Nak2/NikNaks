
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
        return origin
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

local GROUND_TRACE_OFFSET = Vector(0, 0, 10)

---@class AI_SmartLinkResult
---@field hull HULL
---@field move AI_MOVE_FLAGS

---Calculates what links would be created between two positions without applying them.
---@param posA Vector
---@param posB Vector
---@param isAir boolean?  -- true if either node is an air node
---@return AI_SmartLinkResult[]
function NikNaks.Path.AI.CalculateSmartLink(posA, posB, isAir)
    local heightDiff = posA.z - posB.z
    local results = {}

    for hull = 0, NikNaks.HULL.NUM_HULLS - 1 do
        local mins = HULL_MINS[hull]
        local maxs = HULL_MAXS[hull]
        if not mins or not maxs then continue end

        local raisedA = posA + GROUND_TRACE_OFFSET
        local raisedB = posB + GROUND_TRACE_OFFSET

        if util.TraceHull({
            start  = raisedA,
            endpos = raisedB,
            mins   = mins,
            maxs   = maxs,
            mask   = MASK_NPCSOLID,
        }).Hit then continue end

        local move = NikNaks.Path.AI.MoveFlags.None

        if isAir then
            move = NikNaks.Path.AI.MoveFlags.Fly
        elseif math.abs(heightDiff) > (HULL_SAFE_DROP[hull] or 150) then
            move = NikNaks.Path.AI.MoveFlags.Jump
        else
            local diff   = raisedB - raisedA
            local dist   = diff:Length()
            local step   = math.max(maxs.x - mins.x, 32)
            local steps  = math.max(math.floor(dist / step), 1)
            local hasGap = false

            for i = 1, steps - 1 do
                local samplePos = raisedA + diff * (i / steps)
                if not util.TraceHull({
                    start  = samplePos,
                    endpos = samplePos - Vector(0, 0, 74),
                    mins   = Vector(mins.x, mins.y, 0),
                    maxs   = Vector(maxs.x, maxs.y, 4),
                    mask   = MASK_SOLID_BRUSHONLY,
                }).Hit then
                    hasGap = true
                    break
                end
            end

            move = hasGap and NikNaks.Path.AI.MoveFlags.Jump or NikNaks.Path.AI.MoveFlags.Ground
        end

        if move ~= NikNaks.Path.AI.MoveFlags.None then
            results[#results + 1] = { hull = hull, move = move }
        end
    end

    return results
end

---Automatically creates smart links between two nodes.
---@param other AI_Node
function meta:SmartLink(other)
    local isAir = self._type == NikNaks.Path.AI.NodeTypes.Air
        or other._type == NikNaks.Path.AI.NodeTypes.Air

    local results = NikNaks.Path.AI.CalculateSmartLink(self:GetPos(), other:GetPos(), isAir)
    for _, r in ipairs(results) do
        self:SetLinkMoveDirect(other, r.hull, r.move)
    end
end
