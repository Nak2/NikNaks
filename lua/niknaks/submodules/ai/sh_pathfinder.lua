
NikNaks.Path.AI = NikNaks.Path.AI or {}
NikNaks.Path.AI.NetworkMeta = NikNaks.Path.AI.NetworkMeta or {}

---@class AI_Network
local meta = NikNaks.Path.AI.NetworkMeta

---@class AI_PathSettings
---@field hull HULL                      -- Hull type to pathfind for
---@field moveCost number?               -- Cost multiplier for normal movement (default 1.0)
---@field jumpCost number?               -- Cost multiplier for jump links (default 2.0)
---@field climbCost number?              -- Cost multiplier for climb nodes (default 2.0)
---@field maxCost number?                -- Abort if path cost exceeds this (default math.huge)
---@field maxJumpDistance number?        -- Maximum horizontal distance allowed for jump links (default unlimited)
---@field maxJumpUp number?              -- Maximum upward height allowed for jump links (default 128)
---@field maxJumpDown number?            -- Maximum downward drop allowed for jump links (default unlimited)
---@field smoothPath boolean?            -- Will smooth out the path. Defaults to true.
---@field maxSmoothDistance number?      -- Maximum straight-line distance allowed when skipping nodes during smoothing (default unlimited)
---@field allowedMoveFlags AI_MOVE_FLAGS?-- A flag list of allowed moves
---@field class string?                  -- NPC class name for dynamic link / controller filtering (e.g. "npc_citizen")
---@field filter fun(ent:Entity):boolean? | Entity | Entity[] | nil -- If set, will ignore this entity when checking for line of sight in path smoothing (e.g. the NPC itself)
---@field nodeHintFilter AI_InfoNodeType? -- If set, only nodes with this exact hint type are traversable (e.g. HintTypes.StriderNode for Striders)

---@class AI_Path
---@field nodes AI_Node[]        -- Ordered list of nodes from start to goal
---@field moves AI_MOVE_FLAGS[]  -- moves[i] is the move type from nodes[i] to nodes[i+1]

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


local GROUND_TRACE_OFFSET = Vector(0, 0, 8)

-- Persistent trace tables — reused every call to avoid per-trace table allocation.
local _canSkipA   = Vector()
local _canSkipB   = Vector()
local _canSkipSmp = Vector()

local _trLOS = {
    start  = _canSkipA,
    endpos = _canSkipB,
    mins   = nil,
    maxs   = nil,
    mask   = MASK_NPCSOLID,
    filter = nil,
}
local _trGround = {
    start  = Vector(),
    endpos = Vector(),
    mins   = Vector(),
    maxs   = Vector(),
    mask   = MASK_SOLID_BRUSHONLY,
}

local function hasGroundBelow(pos, hullMins, hullMaxs)
    local sx = pos.x;  local sy = pos.y;  local sz = pos.z + 8
    _trGround.start.x  = sx;              _trGround.start.y  = sy;  _trGround.start.z  = sz
    _trGround.endpos.x = sx;              _trGround.endpos.y = sy;  _trGround.endpos.z = sz - 74
    _trGround.mins.x   = hullMins.x - 5; _trGround.mins.y   = hullMins.y - 5; _trGround.mins.z = 0
    _trGround.maxs.x   = hullMaxs.x + 5; _trGround.maxs.y   = hullMaxs.y + 5; _trGround.maxs.z = 4
    return util.TraceHull(_trGround).Hit
end

---@param a AI_Node
---@param b AI_Node
---@param hull HULL
---@param isFlying boolean
---@param filter fun(ent:Entity):boolean? | Entity | Entity[] | nil
---@return boolean
local function canSkip(a, b, hull, isFlying, filter)
    local ap       = a:GetPos()
    local bp       = b:GetPos()
    local hullMins = HULL_MINS[hull] or HULL_MINS[NikNaks.HULL.SMALL_CENTERED]
    local hullMaxs = HULL_MAXS[hull] or HULL_MAXS[NikNaks.HULL.SMALL_CENTERED]
    local oz       = GROUND_TRACE_OFFSET.z

    _canSkipA.x = ap.x; _canSkipA.y = ap.y; _canSkipA.z = ap.z + oz
    _canSkipB.x = bp.x; _canSkipB.y = bp.y; _canSkipB.z = bp.z + oz
    _trLOS.mins   = hullMins
    _trLOS.maxs   = hullMaxs
    _trLOS.filter = filter
    if util.TraceHull(_trLOS).Hit then return false end

    if not isFlying then
        local dx    = _canSkipB.x - _canSkipA.x
        local dy    = _canSkipB.y - _canSkipA.y
        local dz    = _canSkipB.z - _canSkipA.z
        local dist  = math.sqrt(dx * dx + dy * dy + dz * dz)
        local step  = math.max(hullMaxs.x - hullMins.x, 32)
        local steps = math.max(math.floor(dist / step), 2)
        local inv   = 1 / steps
        for i = 1, steps - 1 do
            local t = i * inv
            _canSkipSmp.x = _canSkipA.x + dx * t
            _canSkipSmp.y = _canSkipA.y + dy * t
            _canSkipSmp.z = _canSkipA.z + dz * t
            if not hasGroundBelow(_canSkipSmp, hullMins, hullMaxs) then return false end
        end
    end

    return true
end


-- Persistent A* scratch tables — reused across calls to avoid per-call GC pressure.
-- _touched tracks every node written this run for O(explored) cleanup.
local _g          = {}
local _parent     = {}
local _parentMove = {}
local _closed     = {}
local _openCost   = {}
local _openNode   = {}
local _heapSize   = 0
local _touched    = {}
local _touchedN   = 0

local function _heapPush(cost, node)
    _heapSize            = _heapSize + 1
    _openCost[_heapSize] = cost
    _openNode[_heapSize] = node
    local i = _heapSize
    while i > 1 do
        local p = bit.rshift(i, 1)
        if _openCost[p] <= _openCost[i] then break end
        _openCost[p], _openCost[i] = _openCost[i], _openCost[p]
        _openNode[p], _openNode[i] = _openNode[i], _openNode[p]
        i = p
    end
end

local function _heapPop()
    local node           = _openNode[1]
    _openCost[1]         = _openCost[_heapSize]
    _openNode[1]         = _openNode[_heapSize]
    _openCost[_heapSize] = nil
    _openNode[_heapSize] = nil
    _heapSize            = _heapSize - 1
    local i = 1
    while true do
        local l = i + i
        local r = l + 1
        local s = i
        if l <= _heapSize and _openCost[l] < _openCost[s] then s = l end
        if r <= _heapSize and _openCost[r] < _openCost[s] then s = r end
        if s == i then break end
        _openCost[i], _openCost[s] = _openCost[s], _openCost[i]
        _openNode[i], _openNode[s] = _openNode[s], _openNode[i]
        i = s
    end
    return node
end

local function _astCleanup()
    for i = 1, _touchedN do
        local n        = _touched[i]
        _g[n]          = nil
        _parent[n]     = nil
        _parentMove[n] = nil
        _closed[n]     = nil
        _touched[i]    = nil
    end
    _touchedN = 0
    for i = 1, _heapSize do
        _openCost[i] = nil
        _openNode[i] = nil
    end
    _heapSize = 0
end

---Finds a path between two nodes using A*.
---@param startNode AI_Node
---@param goalNode AI_Node
---@param isFlying boolean
---@param settings AI_PathSettings
---@return AI_Path? -- Path from start to goal, or nil if no path found
function meta:FindPathByNodes(startNode, goalNode, isFlying, settings)
    local hull      = settings.hull      or NikNaks.HULL.SMALL_CENTERED
    local moveCost  = settings.moveCost  or 1.0
    local jumpCost  = settings.jumpCost  or 2.0
    local climbCost = settings.climbCost or 2.0
    local maxCost   = settings.maxCost   or math.huge
    local maxJumpDist = settings.maxJumpDistance
    local maxJumpUp   = settings.maxJumpUp ~= nil and settings.maxJumpUp or 128
    local maxJumpDown = settings.maxJumpDown
    local allowedMoveFlags = settings.allowedMoveFlags
        or isFlying and NikNaks.Path.AI.MoveFlags.Fly
        or NikNaks.Path.AI.MoveFlags.Ground

    local npcClass       = settings.class
    local nodeHintFilter = settings.nodeHintFilter
    local CLIMB_TYPE     = NikNaks.Path.AI.NodeTypes.Climb
    local JUMP_FLAG      = NikNaks.Path.AI.MoveFlags.Jump
    local CLIMB_FLAG     = NikNaks.Path.AI.MoveFlags.Climb
    local FLY_FLAG       = NikNaks.Path.AI.MoveFlags.Fly
    local GROUND_FLAG    = NikNaks.Path.AI.MoveFlags.Ground
    local OVERRIDE_JUMP  = NikNaks.Path.AI.HintTypes.OverrideJumpPermission
    local goalPos        = goalNode:GetPos()

    -- Zone early-exit: two nodes in different zones are never connected
    if startNode._zone ~= goalNode._zone then return nil end

    -- Initialise persistent state for this run
    _heapSize         = 1
    _openCost[1]      = startNode:GetPos():Distance(goalPos)
    _openNode[1]      = startNode
    _g[startNode]     = 0
    _touchedN         = 1
    _touched[1]       = startNode

    while _heapSize > 0 do
        local current = _heapPop()
        if current == goalNode then
            -- Reconstruct path in reverse order, then flip both arrays
            local nodeRev = {}
            local moveRev = {}
            local node = goalNode
            while node do
                nodeRev[#nodeRev + 1] = node
                if _parent[node] then
                    moveRev[#moveRev + 1] = _parentMove[node]
                end
                node = _parent[node]
            end
            local n = #nodeRev
            local nodes = {}
            local moves = {}
            for i = 1, n do nodes[i] = nodeRev[n + 1 - i] end
            for i = 1, #moveRev do moves[i] = moveRev[#moveRev + 1 - i] end
            _astCleanup()
            local path = { nodes = nodes, moves = moves }
            if settings.smoothPath == false then return path end
            return self:SmoothPath(path, hull, isFlying, settings)
        elseif not _closed[current] then
            _closed[current] = true

            local curPos      = current:GetPos()
            local gCurrent    = _g[current]
            local curDynLinks = current:LocateDynamicLinks()
            local curCtrls    = current._controllers
            -- Cache current node's hint type once per node expansion (used for OverrideJumpPermission)
            local curHintType = current:GetHintType()

            for neighbour, hullMoves in pairs(current:GetLinks()) do
                if _closed[neighbour] then continue end
                -- Pre-declare all locals used after any goto/continue so Lua's
                -- scope rules are satisfied without forward-declaration issues
                local dist, linkCost, gNew, gNbr, nbrCtrls, nbrPos, nbrDynLinks, sharedLink, nbrType, isJump, isClimb

                -- Node hint filter: skip nodes that don't have the required hint type
                local nbrHintType
                if nodeHintFilter then
                    nbrHintType = neighbour:GetHintType()
                    if nbrHintType ~= nodeHintFilter then goto _nextNeighbour end
                end

                -- Mask hull moves against allowed flags in one step (allowedMoveFlags is always set)
                local rawMoves = hullMoves[hull] or 0
                local moves    = bit.band(rawMoves, allowedMoveFlags)

                -- OverrideJumpPermission: allow jump between two matching hint nodes even if
                -- jump is not in allowedMoveFlags (mirrors Source SDK jump-hint behaviour)
                if bit.band(rawMoves, JUMP_FLAG) ~= 0 and bit.band(allowedMoveFlags, JUMP_FLAG) == 0 then
                    if curHintType == OVERRIDE_JUMP then
                        local nbrHint = nbrHintType or neighbour:GetHintType()
                        if nbrHint == OVERRIDE_JUMP then
                            moves = bit.bor(moves, JUMP_FLAG)
                        end
                    end
                end

                if moves == 0 then continue end

                nbrType = neighbour:GetType()
                if nbrType == CLIMB_TYPE then
                    if bit.band(moves, CLIMB_FLAG) == 0 and not neighbour:IsWalkableClimb() then continue end
                end

                -- Dynamic link check
                if curDynLinks then
                    nbrDynLinks = neighbour:LocateDynamicLinks()
                    if nbrDynLinks then
                        for _, dl in ipairs(curDynLinks) do
                            for _, ndl in ipairs(nbrDynLinks) do
                                if dl == ndl then sharedLink = dl; break end
                            end
                            if sharedLink then break end
                        end
                    end
                end
                if sharedLink then
                    if sharedLink.moveType ~= 0 then
                        moves = bit.band(moves, sharedLink.moveType)
                        if moves == 0 then goto _nextNeighbour end
                    end
                    if not sharedLink.enabled then
                        local cls = sharedLink.alwaysAllowClass
                        local ok = cls and cls ~= "" and npcClass and ((cls == npcClass) ~= sharedLink.invertedAllow)
                        if not ok then goto _nextNeighbour end
                    end
                end

                -- Controller check
                if curCtrls and curCtrls[1] then
                    for _, ctrl in ipairs(curCtrls) do
                        if ctrl.enabled then
                            local cls = ctrl.alwaysAllowClass
                            local ok = cls and cls ~= "" and npcClass and ((cls == npcClass) ~= ctrl.invertedAllow)
                            if not ok then goto _nextNeighbour end
                        end
                    end
                end
                nbrCtrls = neighbour._controllers
                if nbrCtrls and nbrCtrls[1] then
                    for _, ctrl in ipairs(nbrCtrls) do
                        if ctrl.enabled then
                            local cls = ctrl.alwaysAllowClass
                            local ok = cls and cls ~= "" and npcClass and ((cls == npcClass) ~= ctrl.invertedAllow)
                            if not ok then goto _nextNeighbour end
                        end
                    end
                end

                nbrPos = neighbour:GetPos()
                dist   = curPos:Distance(nbrPos)

                isJump = bit.band(moves, JUMP_FLAG) ~= 0
                if isJump then
                    local heightDiff = nbrPos.z - curPos.z
                    if heightDiff > maxJumpUp                          then goto _nextNeighbour end
                    if maxJumpDown and heightDiff < -maxJumpDown       then goto _nextNeighbour end
                    if maxJumpDist and dist       >  maxJumpDist       then goto _nextNeighbour end
                end

                isClimb  = nbrType == CLIMB_TYPE and bit.band(moves, CLIMB_FLAG) ~= 0
                linkCost = dist * moveCost
                if isJump  then linkCost = linkCost * jumpCost  end
                if isClimb then linkCost = linkCost * climbCost end

                gNew = gCurrent + linkCost
                gNbr = _g[neighbour]
                if gNew <= maxCost and (not gNbr or gNew < gNbr) then
                    if not gNbr then   -- first visit: register for cleanup
                        _touchedN          = _touchedN + 1
                        _touched[_touchedN] = neighbour
                    end
                    _g[neighbour]      = gNew
                    _parent[neighbour] = current
                    local pMove
                    if isClimb then
                        pMove = CLIMB_FLAG
                    elseif bit.band(moves, FLY_FLAG) ~= 0 then
                        pMove = FLY_FLAG
                    elseif isJump then
                        pMove = JUMP_FLAG
                    else
                        pMove = GROUND_FLAG
                    end
                    _parentMove[neighbour] = pMove
                    _heapPush(gNew + nbrPos:Distance(goalPos), neighbour)
                end
                ::_nextNeighbour::
            end
        end
    end

    _astCleanup()
    return nil
end

-- Persistent position proxy — reused in FindPath to avoid a table+closure alloc per call.
-- Update _proxyVec's components before passing _proxy to canSkip.
local _proxyVec = Vector(0, 0, 0)
local _proxy    = { GetPos = function() return _proxyVec end }

---Finds a path between two world positions using A*.
---@param vecStart Vector
---@param vecGoal Vector
---@param isFlying boolean
---@param settings AI_PathSettings
---@return AI_Path?
function meta:FindPath(vecStart, vecGoal, isFlying, settings)
    local nodeType = isFlying
        and NikNaks.Path.AI.NodeTypes.Air
        or  NikNaks.Path.AI.NodeTypes.Ground

    local startNode = self:FindNearestNode(vecStart, nodeType)

    if not startNode then
        ErrorNoHalt("FindPath: no " .. (isFlying and "air" or "ground") .. " node near start position\n")
        return nil
    end

    local goalNode = self:FindNearestNode(vecGoal, nodeType, nil, startNode._zone)

    if not goalNode then
        ErrorNoHalt("FindPath: no " .. (isFlying and "air" or "ground") .. " node near goal position\n")
        return nil
    end
    if startNode == goalNode then return { nodes = { startNode }, moves = {} } end

    local path = self:FindPathByNodes(startNode, goalNode, isFlying, settings)
    if not path or settings.smoothPath == false then return path end

    -- Phase 2: trim endpoints against the raw world positions.
    -- SmoothPath only connects nodes to nodes; these checks connect the real
    -- start/goal positions to the path, bypassing any overshoot in node placement.
    local hull   = settings.hull or NikNaks.HULL.SMALL_CENTERED
    local filter = settings.filter
    local GROUND = NikNaks.Path.AI.MoveFlags.Ground
    local FLY    = NikNaks.Path.AI.MoveFlags.Fly

    -- Try to drop the last node if second-to-last can walk directly to vecGoal
    if #path.nodes > 1 then
        local lastMove = path.moves[#path.moves]
        if lastMove == GROUND or lastMove == FLY then
            _proxyVec.x, _proxyVec.y, _proxyVec.z = vecGoal.x, vecGoal.y, vecGoal.z
            if canSkip(path.nodes[#path.nodes - 1], _proxy, hull, isFlying, filter) then
                path.nodes[#path.nodes] = nil
                path.moves[#path.moves] = nil
            end
        end
    end

    -- Try to drop the first node if vecStart can walk directly to the second node
    if #path.nodes > 1 then
        local firstMove = path.moves[1]
        if firstMove == GROUND or firstMove == FLY then
            _proxyVec.x, _proxyVec.y, _proxyVec.z = vecStart.x, vecStart.y, vecStart.z
            if canSkip(_proxy, path.nodes[2], hull, isFlying, filter) then
                table.remove(path.nodes, 1)
                table.remove(path.moves, 1)
            end
        end
    end

    return path
end

---Smooths a path by removing nodes that can be skipped via direct line of sight.
---Only ground and fly segments are eligible for smoothing; jump and climb segments are preserved.
---@param path AI_Path
---@param hull HULL
---@param isFlying boolean
---@param settings AI_PathSettings
---@return AI_Path
function meta:SmoothPath(path, hull, isFlying, settings)
    local nodes = path.nodes
    local moves = path.moves
    local n     = #nodes
    if n <= 2 then return path end

    local GROUND     = NikNaks.Path.AI.MoveFlags.Ground
    local FLY        = NikNaks.Path.AI.MoveFlags.Fly
    local smoothMove = isFlying and FLY or GROUND
    local maxDistSqr = settings.maxSmoothDistance and (settings.maxSmoothDistance * settings.maxSmoothDistance)
    local filter     = settings.filter

    -- Smooth backwards: start from the goal and greedily reach as far back as possible.
    -- This prioritises accuracy near the destination, which matters most for NPC behaviour.
    local revNodes = { nodes[n] }
    local revMoves = {}

    local j = n
    while j > 1 do
        local best_i   = j - 1        -- fallback: one step back
        local bestMove = moves[j - 1]

        for i = 1, j - 2 do
            -- Distance cap: skip i values that are too far from j
            if maxDistSqr and nodes[i]:GetPos():DistToSqr(nodes[j]:GetPos()) > maxDistSqr then
                -- no continue keyword; handled by else below
            else
                -- All intermediate segments must be ground or fly
                local canSmooth = true
                for k = i, j - 1 do
                    if moves[k] ~= GROUND and moves[k] ~= FLY then
                        canSmooth = false
                        break
                    end
                end
                if canSmooth and canSkip(nodes[i], nodes[j], hull, isFlying, filter) then
                    best_i   = i
                    bestMove = smoothMove
                    break   -- earliest reachable node found; stop scanning
                end
            end
        end

        revNodes[#revNodes + 1] = nodes[best_i]
        revMoves[#revMoves + 1] = bestMove
        j = best_i
    end

    -- Reverse both arrays to restore start-to-goal order
    local rn         = #revNodes
    local finalNodes = {}
    local finalMoves = {}
    for i = 1, rn do
        finalNodes[i] = revNodes[rn + 1 - i]
    end
    for i = 1, #revMoves do
        finalMoves[i] = revMoves[#revMoves + 1 - i]
    end

    return { nodes = finalNodes, moves = finalMoves }
end

---@class AI_PathState
---@field path AI_Path          -- Current path
---@field currentIndex integer  -- Which node the NPC is currently walking toward
---@field goal Vector           -- Last known goal position
---@field goalNode AI_Node      -- Last known goal node

---Updates a path in-place when the goal has moved, reusing as much as possible.
---@param state AI_PathState
---@param newGoal Vector
---@param isFlying boolean
---@param settings AI_PathSettings
---@return boolean -- false if no path could be found
function meta:UpdatePath(state, newGoal, isFlying, settings)
    local newGoalNode = self:FindNearestNode(newGoal, isFlying
        and NikNaks.Path.AI.NodeTypes.Air
        or  NikNaks.Path.AI.NodeTypes.Ground)

    if not newGoalNode then return false end

    -- Goal node hasn't changed, nothing to do
    if newGoalNode == state.goalNode then
        state.goal = newGoal
        return true
    end

    local pathNodes = state.path.nodes

    -- Find the furthest node ahead in the current path that is still
    -- a good branching point — closest node to the new goal
    local bestIndex = state.currentIndex
    local bestDist  = math.huge
    for i = state.currentIndex, #pathNodes do
        local d = pathNodes[i]:GetPos():DistToSqr(newGoalNode:GetPos())
        if d < bestDist then
            bestDist  = d
            bestIndex = i
        end
    end

    -- Recompute only from bestIndex node to the new goal
    local tail = self:FindPathByNodes(pathNodes[bestIndex], newGoalNode, isFlying, settings)
    if not tail then return false end

    -- Splice: keep head up to bestIndex, append tail (skipping tail[1] which equals head[bestIndex])
    local newNodes = {}
    local newMoves = {}
    for i = 1, bestIndex do
        newNodes[i] = pathNodes[i]
    end
    for i = 1, bestIndex - 1 do
        newMoves[i] = state.path.moves[i]
    end
    for i = 2, #tail.nodes do
        newNodes[#newNodes + 1] = tail.nodes[i]
        newMoves[#newMoves + 1] = tail.moves[i - 1]
    end

    state.path     = { nodes = newNodes, moves = newMoves }
    state.goal     = newGoal
    state.goalNode = newGoalNode

    return true
end

local queue = {}
local function addToQueue(task)
    queue[#queue + 1] = task
    if timer.Exists("NikNaks.AIPathfinderQueue") then return end
    timer.Create("NikNaks.AIPathfinderQueue", 0.01, 0, function()
        -- Grab one task from queue, if queue is empty, stop timer
        local task = table.remove(queue, 1)
        if not task then
            timer.Remove("NikNaks.AIPathfinderQueue")
            return
        end
        local self = task[1]
        local vecStart = task[2]
        local vecGoal = task[3]
        local isFlying = task[4]
        local settings = task[5]
        local callBack = task[6]
        callBack(self:FindPath(vecStart, vecGoal, isFlying, settings))
    end)
end

---Finds a path between two world positions using A*. Asynchronous version that yields periodically to avoid long stalls.
---@param vecStart Vector
---@param vecGoal Vector
---@param isFlying boolean
---@param settings AI_PathSettings
---@param callback fun(path:AI_Path?) Callback to receive the path when found; nil if no path exists
function meta:FindPathAsync(vecStart, vecGoal, isFlying, settings, callback)
    addToQueue({self, vecStart, vecGoal, isFlying, settings, callback})
end
