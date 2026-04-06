
NikNaks.Path.AI = NikNaks.Path.AI or {}
NikNaks.Path.AI.NetworkMeta = NikNaks.Path.AI.NetworkMeta or {}

---@class AI_Network
local meta = NikNaks.Path.AI.NetworkMeta

---@class AI_PathSettings
---@field hull HULL                -- Hull type to pathfind for
---@field moveCost number?         -- Cost multiplier for normal movement (default 1.0)
---@field jumpCost number?         -- Extra flat cost added to jump links (default 100)
---@field climbCost number?        -- Cost multiplier for climb nodes (default 2.0)
---@field maxCost number?          -- Abort if path cost exceeds this (default math.huge)
---@field smoothPath boolean?      -- Will smooth out the path. Defaults to true.
---@field budget integer?          -- For ASync pathfinding. How many steps pr tick.

local HULL_MINS = {
    [NikNaks.HULL.HUMAN]          = Vector(-16, -16, 0),
    [NikNaks.HULL.SMALL_CENTERED] = Vector(-12, -12, -12),
    [NikNaks.HULL.WIDE_HUMAN]     = Vector(-24, -24, 0),
    [NikNaks.HULL.TINY]           = Vector(-8,  -8,  0),
    [NikNaks.HULL.WIDE_SHORT]     = Vector(-36, -36, 0),
    [NikNaks.HULL.MEDIUM]         = Vector(-16, -16, 0),
    [NikNaks.HULL.TINY_CENTERED]  = Vector(-8,  -8,  -8),
    [NikNaks.HULL.LARGE]          = Vector(-32, -32, 0),
    [NikNaks.HULL.LARGE_CENTERED] = Vector(-32, -32, -32),
    [NikNaks.HULL.MEDIUM_TALL]    = Vector(-16, -16, 0),
}

local HULL_MAXS = {
    [NikNaks.HULL.HUMAN]          = Vector(16,  16,  72),
    [NikNaks.HULL.SMALL_CENTERED] = Vector(12,  12,  12),
    [NikNaks.HULL.WIDE_HUMAN]     = Vector(24,  24,  72),
    [NikNaks.HULL.TINY]           = Vector(8,   8,   16),
    [NikNaks.HULL.WIDE_SHORT]     = Vector(36,  36,  36),
    [NikNaks.HULL.MEDIUM]         = Vector(16,  16,  36),
    [NikNaks.HULL.TINY_CENTERED]  = Vector(8,   8,   8),
    [NikNaks.HULL.LARGE]          = Vector(32,  32,  80),
    [NikNaks.HULL.LARGE_CENTERED] = Vector(32,  32,  32),
    [NikNaks.HULL.MEDIUM_TALL]    = Vector(16,  16,  60),
}

---Finds a path between two nodes using A*.
---@param startNode AI_Node
---@param goalNode AI_Node
---@param isFlying boolean
---@param settings AI_PathSettings
---@return AI_Node[]? -- Ordered list of nodes from start to goal, or nil if no path found
function meta:FindPathByNodes(startNode, goalNode, isFlying, settings)
    local hull      = settings.hull      or NikNaks.HULL.SMALL_CENTERED
    local moveCost  = settings.moveCost  or 1.0
    local jumpCost  = settings.jumpCost  or 100
    local climbCost = settings.climbCost or 2.0
    local maxCost   = settings.maxCost   or math.huge

    -- g: best known cost from start to node
    -- f: g + heuristic (estimated total cost)
    local g       = { [startNode] = 0 }
    local f       = { [startNode] = startNode:GetPos():Distance(goalNode:GetPos()) }
    local parent  = {}
    local closed  = {}

    -- Min-heap open set: { f, node }
    local open     = { { f[startNode], startNode } }
    local openSet  = { [startNode] = true }

    local function heapPush(cost, node)
        local heap = open
        heap[#heap + 1] = { cost, node }
        local i = #heap
        while i > 1 do
            local p = math.floor(i / 2)
            if heap[p][1] <= heap[i][1] then break end
            heap[p], heap[i] = heap[i], heap[p]
            i = p
        end
    end

    local function heapPop()
        local heap = open
        local top  = heap[1]
        local n    = #heap
        heap[1]    = heap[n]
        heap[n]    = nil
        local i    = 1
        while true do
            local l, r, s = i * 2, i * 2 + 1, i
            if l <= #heap and heap[l][1] < heap[s][1] then s = l end
            if r <= #heap and heap[r][1] < heap[s][1] then s = r end
            if s == i then break end
            heap[i], heap[s] = heap[s], heap[i]
            i = s
        end
        return top
    end

    while #open > 0 do
        local current = heapPop()[2]
        if current == goalNode then
            -- Reconstruct path
            local path = {}
            local node = goalNode
            while node do
                path[#path + 1] = node
                node = parent[node]
            end
            -- Reverse
            local i, j = 1, #path
            while i < j do
                path[i], path[j] = path[j], path[i]
                i, j = i + 1, j - 1
            end
            if settings.smoothPath == false then return path end
            return self:SmoothPath(path, hull, isFlying)
        end

        closed[current]  = true
        openSet[current] = nil

        for neighbour, hullMoves in pairs(current:GetLinks()) do
            if closed[neighbour] then continue end
            local moves = hullMoves[hull] or 0
            if moves == 0 then continue end

            -- Skip mid-ladder nodes for hulls that can't climb
            if neighbour:GetType() == NikNaks.Path.AI.NodeTypes.Climb then
                local canClimb = bit.band(moves, NikNaks.Path.AI.MoveFlags.Climb) ~= 0
                if not canClimb and not neighbour:IsWalkableClimb() then continue end
            end

            -- Base cost: 3D distance between nodes
            local dist     = current:GetPos():Distance(neighbour:GetPos())
            local linkCost = dist * moveCost

            -- Jump penalty
            if bit.band(moves, NikNaks.Path.AI.MoveFlags.Jump) ~= 0 then
                linkCost = linkCost + jumpCost
            end

            -- Climb multiplier (only for actual climbing, not walkable entry/exit points)
            if neighbour:GetType() == NikNaks.Path.AI.NodeTypes.Climb then
                if bit.band(moves, NikNaks.Path.AI.MoveFlags.Climb) ~= 0 then
                    linkCost = linkCost * climbCost
                end
            end

            local gNew = g[current] + linkCost
            if gNew > maxCost then continue end

            if not g[neighbour] or gNew < g[neighbour] then
                g[neighbour]      = gNew
                f[neighbour]      = gNew + neighbour:GetPos():Distance(goalNode:GetPos())
                parent[neighbour] = current
                if not openSet[neighbour] then
                    openSet[neighbour] = true
                    heapPush(f[neighbour], neighbour)
                end
            end
        end
    end

    return nil  -- no path found
end

---Finds a path between two world positions using A*.
---@param vecStart Vector
---@param vecGoal Vector
---@param isFlying boolean
---@param settings AI_PathSettings
---@return AI_Node[]?
function meta:FindPath(vecStart, vecGoal, isFlying, settings)
    local nodeType = isFlying
        and NikNaks.Path.AI.NodeTypes.Air
        or  NikNaks.Path.AI.NodeTypes.Ground

    local startNode = self:FindNearestNode(vecStart, nodeType)
    local goalNode  = self:FindNearestNode(vecGoal,  nodeType)

    if not startNode then
        ErrorNoHalt("FindPath: no " .. (isFlying and "air" or "ground") .. " node near start position\n")
        return nil
    end
    if not goalNode then
        ErrorNoHalt("FindPath: no " .. (isFlying and "air" or "ground") .. " node near goal position\n")
        return nil
    end
    if startNode == goalNode then return { startNode } end

    return self:FindPathByNodes(startNode, goalNode, isFlying, settings)
end

local GROUND_TRACE_OFFSET = Vector(0, 0, 10)
local function hasGroundBelow(pos, hull)
    local mins = HULL_MINS[hull] or HULL_MINS[NikNaks.HULL.SMALL_CENTERED]
    local maxs = HULL_MAXS[hull] or HULL_MAXS[NikNaks.HULL.SMALL_CENTERED]
    local hullMins = Vector(mins.x, mins.y, 0)
    local hullMaxs = Vector(maxs.x, maxs.y, 4)
    local raised = pos + GROUND_TRACE_OFFSET
    return not util.TraceHull({
        start  = raised,
        endpos = raised - Vector(0, 0, 74),  -- 64 + 10 to keep the same ground detection range
        mins   = hullMins,
        maxs   = hullMaxs,
        mask   = MASK_SOLID_BRUSHONLY,
    }).Hit == false
end

local function canSkip(a, b, hull, isFlying)
    local aPos = a:GetPos() + GROUND_TRACE_OFFSET
    local bPos = b:GetPos() + GROUND_TRACE_OFFSET

    if util.TraceHull({
        start  = aPos,
        endpos = bPos,
        mins   = HULL_MINS[hull] or HULL_MINS[NikNaks.HULL.SMALL_CENTERED],
        maxs   = HULL_MAXS[hull] or HULL_MAXS[NikNaks.HULL.SMALL_CENTERED],
        mask   = MASK_NPCSOLID,
    }).Hit then return false end

    if not isFlying then
        local diff    = bPos - aPos
        local dist    = diff:Length()
        local mins    = HULL_MINS[hull] or HULL_MINS[NikNaks.HULL.SMALL_CENTERED]
        local maxs    = HULL_MAXS[hull] or HULL_MAXS[NikNaks.HULL.SMALL_CENTERED]
        -- Sample every (hull width) units along the path so no gap wider than the NPC is missed
        local step    = math.max(maxs.x - mins.x, 32)  -- at least every 32 units
        local steps   = math.max(math.floor(dist / step), 1)
        for i = 1, steps - 1 do
            if not hasGroundBelow(aPos + diff * (i / steps), hull) then return false end
        end
    end

    return true
end

---Smooths a path by removing nodes that can be skipped via direct line of sight.
---@param path AI_Node[]
---@param hull HULL
---@return AI_Node[]
function meta:SmoothPath(path, hull, isFlying)
    if #path <= 2 then return path end
    local smoothed = { path[1] }
    local i = 1
    while i < #path do
        local j = #path
        while j > i + 1 do
            if canSkip(path[i], path[j], hull, isFlying) then break end
            j = j - 1
        end
        smoothed[#smoothed + 1] = path[j]
        i = j
    end
    return smoothed
end

---@class AI_PathState
---@field path AI_Node[]        -- Current path
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

    -- Find the furthest node ahead in the current path that is still
    -- a good branching point — closest node to the new goal
    local bestIndex = state.currentIndex
    local bestDist  = math.huge
    for i = state.currentIndex, #state.path do
        local d = state.path[i]:GetPos():DistToSqr(newGoalNode:GetPos())
        if d < bestDist then
            bestDist  = d
            bestIndex = i
        end
    end

    -- Recompute only from bestIndex node to the new goal
    local tail = self:FindPathByNodes(state.path[bestIndex], newGoalNode, isFlying, settings)
    if not tail then return false end

    -- Splice: keep path up to bestIndex, append new tail
    local newPath = {}
    for i = 1, bestIndex do
        newPath[i] = state.path[i]
    end
    for i = 2, #tail do  -- skip tail[1] since it's already at bestIndex
        newPath[#newPath + 1] = tail[i]
    end

    state.path      = newPath
    state.goal      = newGoal
    state.goalNode  = newGoalNode

    return true
end

---Finds a path asynchronously using a coroutine, calling callback when done.
---@param vecStart Vector
---@param vecGoal Vector
---@param isFlying boolean
---@param settings AI_PathSettings
---@param callback fun(path: AI_Node[]|nil)
function meta:FindPathAsync(vecStart, vecGoal, isFlying, settings, callback)
    local nodeType = isFlying
        and NikNaks.Path.AI.NodeTypes.Air
        or  NikNaks.Path.AI.NodeTypes.Ground

    local startNode = self:FindNearestNode(vecStart, nodeType)
    local goalNode  = self:FindNearestNode(vecGoal,  nodeType)

    if not startNode or not goalNode then
        callback(nil)
        return
    end

    if startNode == goalNode then
        callback({ startNode })
        return
    end

    local hull      = settings.hull      or NikNaks.HULL.SMALL_CENTERED
    local moveCost  = settings.moveCost  or 1.0
    local jumpCost  = settings.jumpCost  or 100
    local climbCost = settings.climbCost or 2.0
    local maxCost   = settings.maxCost   or math.huge

    -- Budget: max nodes to expand per tick before yielding
    local BUDGET = settings.budget or 50

    local co = coroutine.create(function()
        local g      = { [startNode] = 0 }
        local f      = { [startNode] = startNode:GetPos():Distance(goalNode:GetPos()) }
        local parent = {}
        local closed = {}
        local open    = { { f[startNode], startNode } }
        local openSet = { [startNode] = true }

        local function heapPush(cost, node)
            local heap = open
            heap[#heap + 1] = { cost, node }
            local i = #heap
            while i > 1 do
                local p = math.floor(i / 2)
                if heap[p][1] <= heap[i][1] then break end
                heap[p], heap[i] = heap[i], heap[p]
                i = p
            end
        end

        local function heapPop()
            local heap = open
            local top  = heap[1]
            local n    = #heap
            heap[1]    = heap[n]
            heap[n]    = nil
            local i    = 1
            while true do
                local l, r, s = i * 2, i * 2 + 1, i
                if l <= #heap and heap[l][1] < heap[s][1] then s = l end
                if r <= #heap and heap[r][1] < heap[s][1] then s = r end
                if s == i then break end
                heap[i], heap[s] = heap[s], heap[i]
                i = s
            end
            return top
        end

        local expanded = 0
        while #open > 0 do
            local current = heapPop()[2]

            if current == goalNode then
                local path = {}
                local node = goalNode
                while node do
                    path[#path + 1] = node
                    node = parent[node]
                end
                local i, j = 1, #path
                while i < j do
                    path[i], path[j] = path[j], path[i]
                    i, j = i + 1, j - 1
                end
                if settings.smoothPath ~= false then
                    coroutine.yield("smooth", path)  -- signal to smooth outside coroutine
                else
                    coroutine.yield("done", path)
                end
                return
            end

            closed[current]  = true
            openSet[current] = nil

            for neighbour, hullMoves in pairs(current:GetLinks()) do
                if closed[neighbour] then continue end
                local moves = hullMoves[hull] or 0
                if moves == 0 then continue end

                if neighbour:GetType() == NikNaks.Path.AI.NodeTypes.Climb then
                    local canClimb = bit.band(moves, NikNaks.Path.AI.MoveFlags.Climb) ~= 0
                    if not canClimb and not neighbour:IsWalkableClimb() then continue end
                end

                local dist     = current:GetPos():Distance(neighbour:GetPos())
                local linkCost = dist * moveCost

                if bit.band(moves, NikNaks.Path.AI.MoveFlags.Jump) ~= 0 then
                    linkCost = linkCost + jumpCost
                end

                if neighbour:GetType() == NikNaks.Path.AI.NodeTypes.Climb then
                    if bit.band(moves, NikNaks.Path.AI.MoveFlags.Climb) ~= 0 then
                        linkCost = linkCost * climbCost
                    end
                end

                local gNew = g[current] + linkCost
                if gNew > maxCost then continue end

                if not g[neighbour] or gNew < g[neighbour] then
                    g[neighbour]      = gNew
                    f[neighbour]      = gNew + neighbour:GetPos():Distance(goalNode:GetPos())
                    parent[neighbour] = current
                    if not openSet[neighbour] then
                        openSet[neighbour] = true
                        heapPush(f[neighbour], neighbour)
                    end
                end
            end

            expanded = expanded + 1
            if expanded >= BUDGET then
                expanded = 0
                coroutine.yield("continue")
            end
        end

        coroutine.yield("done", nil)
    end)

    -- Drive the coroutine one step per tick
    local function step()
        local ok, status, result = coroutine.resume(co)
        if not ok then
            ErrorNoHalt("FindPathAsync coroutine error: " .. tostring(status) .. "\n")
            callback(nil)
            return
        end
        if status == "continue" then
            timer.Simple(0, step)  -- resume next tick
        elseif status == "smooth" then
            callback(self:SmoothPath(result, hull, isFlying))
        elseif status == "done" then
            callback(result)
        end
    end

    timer.Simple(0, step)
end