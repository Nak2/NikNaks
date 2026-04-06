local format                = string.format
local NUM_HULLS             = NikNaks.HULL.NUM_HULLS
NikNaks.Path.AI             = NikNaks.Path.AI or {}
NikNaks.Path.AI.NetworkMeta = NikNaks.Path.AI.NetworkMeta or {}

local network               = nil
local networkFailed         = false
local retryTime             = nil

---Returns the AI network for the current map, or false if unavailable.
---@return AI_Network|false
function NikNaks.Path.AI.GetNetwork()
    if networkFailed then return false end
    if network then return network end
    if retryTime and CurTime() < retryTime then
        networkFailed = true
        return false
    end

    -- No info_node entities means no AIN will ever exist for this map
    if #NikNaks.CurrentMap:FindByClass("info_node") == 0 then
        networkFailed = true
        ErrorNoHalt("NikNaks: map has no info_node entities, AIN unavailable\n")
        return false
    end

    local buffer = NikNaks.BitBuffer.OpenFile("maps/graphs/" .. game.GetMap() .. ".ain", "GAME")
    if not buffer then
        -- Only retry if server just started — AIN may still be compiling
        if not retryTime and CurTime() < 5 then
            retryTime = CurTime() + 5
            ErrorNoHalt("AI Network: failed to load AIN, retry in 5 seconds\n")
        else
            networkFailed = true
            ErrorNoHalt("AI Network: failed to load AIN, giving up\n")
        end
        return false
    end

    network = NikNaks.Path.AI.ReadAIN(buffer)
    retryTime = nil
    return network
end

---@class AI_Network
---@field _version integer The AIN version
---@field _mapVersion integer The map revision version. If smaller, will recompile.
---@field _nodes AI_Node[]
---@field _graph table<string, AI_Node> -- Fast lookup table for nodes
---@field _entityLookup table<integer, AI_Node>
local meta = NikNaks.Path.AI.NetworkMeta
meta.__index = meta

local obj_tostring = "AI Network [%s nodes]"
meta.__tostring = function(self)
    return format(obj_tostring, table.Count(self._nodes))
end

---Reads a node from a bitbuffer
---@param buffer BitBuffer
---@return AI_Node
local function readNode(buffer)
    ---@class AI_Node
    local t = setmetatable({}, NikNaks.Path.AI.NodeMeta)
    t._pos = buffer:ReadVector()
    t._rawpos = t._pos
    t._yaw = buffer:ReadFloat()
    t._offsets = {}
    for i = 0, NUM_HULLS - 1 do
        t._offsets[i] = buffer:ReadFloat() -- Float
    end
    t._type = buffer:ReadByte()            -- Byte
    t._info = buffer:ReadUShort()          -- UShort
    t._zone = buffer:ReadShort()
    t._links = {}

    -- Clamp Invalid
    if t._type <= NikNaks.Path.AI.NodeTypes.Invalid or t._type >= (NikNaks.Path.AI.NodeTypes.Water) then
        t._type = NikNaks.Path.AI.NodeTypes.Invalid
    end

    return t
end

---Reads a link from a file
---@param buffer BitBuffer
---@param nodeFile AI_Network
local function readLink(buffer, nodeFile)
    local node1 = nodeFile._nodes[buffer:ReadShort()]
    local node2 = nodeFile._nodes[buffer:ReadShort()]

    if not node1 or not node2 then
        ErrorNoHalt("Invalid link: " .. tostring(node1) .. " <-> " .. tostring(node2))
        return
    end

    if not node1._links[node2] then node1._links[node2] = {} end
    if not node2._links[node1] then node2._links[node1] = {} end
    for i = 0, NUM_HULLS - 1 do
        local move = buffer:ReadByte()
        node1._links[node2][i] = move
        node2._links[node1][i] = move
    end
end

---Reads the buffer as an AI_Network.
---@param buffer BitBuffer
---@return AI_Network
function NikNaks.Path.AI.ReadAIN(buffer)
    ---@class AI_Network
    local nodeFile         = setmetatable({}, meta)

    nodeFile._version      = buffer:ReadLong()
    nodeFile._mapVersion   = buffer:ReadLong()
    nodeFile._nodes        = {}
    nodeFile._graph        = {}
    nodeFile._entityLookup = {}

    local lookupTable      = NikNaks.Path.AI.GetLookupTable()

    -- Load nodes
    local num_nodes        = buffer:ReadLong()
    for i = 0, num_nodes - 1 do
        local node = readNode(buffer)
        node._file = nodeFile
        node:SetPos(node:GetRawPos())
        nodeFile._nodes[i] = node
        if (lookupTable[i] == nil) then continue end
        node:SetLookupLinkIndex(i)
    end

    -- Load links
    local num_links = buffer:ReadLong()
    for _ = 1, num_links do
        readLink(buffer, nodeFile)
    end

    -- Load lookup table
    for i = 0, num_nodes - 1 do
        buffer:ReadLong()
    end

    return nodeFile
end

---Writes a node to a bitbuffer
---@param node AI_Node
---@param buffer BitBuffer
local function writeNode(node, buffer)
    buffer:WriteVector(node:GetRawPos())
    buffer:WriteFloat(node._yaw)
    for i = 0, NUM_HULLS - 1 do
        buffer:WriteFloat(node._offsets[i] or 0) -- or 0 guards empty dummy offsets
    end
    buffer:WriteByte(node:GetType())
    buffer:WriteUShort(node:GetType() == NikNaks.Path.AI.NodeTypes.Climb and node._info or 0)
    buffer:WriteShort(node._zone)
end

---Writes a link to a file
---@param node1 AI_Node
---@param node2 AI_Node
---@param node1_id integer
---@param node2_id integer
---@param buffer BitBuffer
local function writeLink(node1_id, node1, node2_id, node2, buffer)
    buffer:WriteShort(node1_id)
    buffer:WriteShort(node2_id)
    local moves = node1._links[node2]
    for i = 0, NUM_HULLS - 1 do
        buffer:WriteByte(moves and moves[i] or 0)
    end
end

---Assigns a zone ID to a node and all nodes reachable from it.
---@param newZone integer
---@param startNode AI_Node
---@param usedNodes table<AI_Node, boolean>
---@param file AI_Network
local function floodFillZone(newZone, startNode, usedNodes, file)
    local queue = { startNode }
    local head  = 1
    while head <= #queue do
        local node = queue[head]
        head = head + 1
        if usedNodes[node] then continue end
        usedNodes[node] = true
        node._zone = newZone

        for neighbour in pairs(node:GetLinks()) do
            if not usedNodes[neighbour] then
                queue[#queue + 1] = neighbour
            end
        end

        for _, dynamicLink in pairs(node:LocateDynamicLinks() or {}) do
            local n1 = file._entityLookup[dynamicLink.startNode]
            local n2 = file._entityLookup[dynamicLink.endNode]
            if n1 and not usedNodes[n1] then queue[#queue + 1] = n1 end
            if n2 and not usedNodes[n2] then queue[#queue + 1] = n2 end
        end
    end
end

---Rebuilds zone IDs from node connectivity.
---@param self AI_Network
local function RebuildZones(self)
    local visited = {}
    local zoneNum = 0
    for _, node in pairs(self._nodes) do
        if visited[node] then continue end
        floodFillZone(zoneNum, node, visited, self)
        zoneNum = zoneNum + 1
    end
end

---Writes the AI_Network to a buffer in AIN format.
---@param overrideRevision boolean -- Will max the map revision, preventing it from being outdated
---@return BitBuffer
function meta:WriteToBuffer(overrideRevision)
    RebuildZones(self)
    local buffer = NikNaks.BitBuffer.Create()
    buffer:WriteLong(self._version)
    buffer:WriteLong(overrideRevision and 0x7FFFFFFF or NikNaks.CurrentMap:GetMapRevision())

    local dummyNode = {
        _type    = NikNaks.Path.AI.NodeTypes.Invalid,
        _pos     = Vector(0, 0, 0),
        _rawpos  = Vector(0, 0, 0),
        _yaw     = 0,
        _offsets = {},
        _info    = 0,
        _zone    = 0,
        _links   = {},
    }
    setmetatable(dummyNode, NikNaks.Path.AI.NodeMeta)

    -- Step 1: populate reserved slots from entity lookup. Place dummy for entries with no claiming node
    ---@type table<integer, AI_Node>
    local nodeTab = {}
    for nodeIndex, node in pairs(self._entityLookup) do
        nodeTab[nodeIndex] = node
    end

    local lookup = NikNaks.Path.AI.GetLookupTable()
    for nodeIndex in pairs(lookup) do
        if not nodeTab[nodeIndex] then
            nodeTab[nodeIndex] = dummyNode
        end
    end

    -- Step 2: fill remaining nodes into any free slot starting at 0
    local nextFree = 0
    for _, node in pairs(self._nodes) do
        if node._lookupId ~= nil then continue end -- already placed in step 1
        while nodeTab[nextFree] do
            nextFree = nextFree + 1
        end
        nodeTab[nextFree] = node
        nextFree = nextFree + 1
    end

    -- Step 3: find the highest occupied index so we know the array bounds
    local maxIndex = nextFree - 1
    for i in pairs(nodeTab) do
        if i > maxIndex then maxIndex = i end
    end

    -- Step 4: fill gaps with dummy (Invalid) nodes
    for i = 0, maxIndex do
        if not nodeTab[i] then
            nodeTab[i] = dummyNode
        end
    end

    -- Step 5: Write nodes
    buffer:WriteLong(maxIndex + 1)
    for i = 0, maxIndex do
        writeNode(nodeTab[i], buffer)
    end

    -- Step 6: Write links
    local nodeIndex = {}
    for i = 0, maxIndex do
        nodeIndex[nodeTab[i]] = i
    end

    local written  = {}
    local linkData = {}
    for i = 0, maxIndex do
        local node = nodeTab[i]
        for neighbour, _ in pairs(node._links) do
            local ni = nodeIndex[neighbour]
            if ni == nil then continue end
            if written[node] and written[node][neighbour] then continue end
            written[node]            = written[node] or {}
            written[neighbour]       = written[neighbour] or {}
            written[node][neighbour] = true
            written[neighbour][node] = true
            linkData[#linkData + 1]  = { i, node, ni, neighbour }
        end
    end

    buffer:WriteLong(#linkData)
    for _, link in ipairs(linkData) do
        writeLink(link[1], link[2], link[3], link[4], buffer)
    end

    -- Step 7: Write the lookup entity-table
    for i = 0, maxIndex do
        local entry = lookup[i]
        buffer:WriteLong(entry and entry.nodeId or -1)
    end
    return buffer
end

local GRID_SIZE = 1000 -- must match the value in the node file

---Returns the nearest node from the grid within a certain distance.
---@param pos Vector
---@param type AI_NodeType?
---@param maxDistance number?   -- Will default to 1000
---@return AI_Node?
function meta:FindNearestNode(pos, type, maxDistance)
    maxDistance      = maxDistance or GRID_SIZE
    local cellRadius = math.ceil(maxDistance / GRID_SIZE)
    local bestNode   = nil
    local bestDist   = maxDistance * maxDistance
    local cx         = math.floor(pos.x / GRID_SIZE)
    local cy         = math.floor(pos.y / GRID_SIZE)
    local isGround   = type == NodeTypes.Ground
    local isAny      = type == NodeTypes.Any or type == nil

    for dx = -cellRadius, cellRadius do
        for dy = -cellRadius, cellRadius do
            local cell = self._graph[(cx + dx) .. "," .. (cy + dy)]
            if not cell then continue end
            for _, node in ipairs(cell) do
                if not isAny and node._type ~= type then
                    if not isGround or node._type ~= NodeTypes.Climb or not node:IsWalkableClimb() then
                        continue
                    end
                end
                local dist = (node:GetPos() - pos):LengthSqr()
                if dist < bestDist then
                    bestDist = dist
                    bestNode = node
                end
            end
        end
    end

    return bestNode
end

---Returns all nodes within a certain distance.
---@param pos Vector
---@param type AI_NodeType?
---@param distance number?
---@return AI_Node[]
function meta:FindNodesByDistance(pos, type, distance)
    distance         = distance or GRID_SIZE
    local cellRadius = math.ceil(distance / GRID_SIZE)
    local distSqr    = distance * distance
    local result     = {}
    local cx         = math.floor(pos.x / GRID_SIZE)
    local cy         = math.floor(pos.y / GRID_SIZE)
    local isGround   = type == NodeTypes.Ground
    local isAny      = type == NodeTypes.Any or type == nil

    for dx = -cellRadius, cellRadius do
        for dy = -cellRadius, cellRadius do
            local cell = self._graph[(cx + dx) .. "," .. (cy + dy)]
            if not cell then continue end
            for _, node in ipairs(cell) do
                if not isAny and node._type ~= type then
                    if not isGround or node._type ~= NodeTypes.Climb or not node:IsWalkableClimb() then
                        continue
                    end
                end
                if (node:GetPos() - pos):LengthSqr() <= distSqr then
                    result[#result + 1] = node
                end
            end
        end
    end

    return result
end

---Adds a new node to the network at the given position.
---@param pos Vector
---@param type AI_NodeType
---@param yaw number?
---@return AI_Node
function meta:AddNode(pos, type, yaw)
    ---@type AI_Node
    local node = setmetatable({}, NikNaks.Path.AI.NodeMeta)
    node._file    = self
    node._type    = type or NikNaks.Path.AI.NodeTypes.Ground
    node._yaw     = yaw or 0
    node._info    = 0
    node._zone    = -1
    node._links   = {}
    node._offsets = {}

    -- Initialize offsets to 0 for all hulls
    for i = 0, NikNaks.HULL.NUM_HULLS - 1 do
        node._offsets[i] = 0
    end

    -- Register in _nodes using next available key
    local idx = table.Count(self._nodes)
    self._nodes[idx] = node

    -- SetPos handles grid registration
    node:SetPos(pos)

    return node
end

---Removes a node from the network, cleaning up all its links and grid entry.
---@param node AI_Node
function meta:RemoveNode(node)
    -- Remove all links to this node
    for neighbour in pairs(node._links) do
        neighbour._links[node] = nil
    end

    -- Remove from grid
    if node._gridKey then
        local cell = self._graph[node._gridKey]
        if cell then
            for i = #cell, 1, -1 do
                if cell[i] == node then
                    cell[i] = cell[#cell]
                    cell[#cell] = nil
                    break
                end
            end
        end
    end

    -- Remove from entity lookup
    if node._lookupId then
        self._entityLookup[node._lookupId] = nil
    end

    -- Remove from nodes table
    for k, v in pairs(self._nodes) do
        if v == node then
            self._nodes[k] = nil
            break
        end
    end
end

---Adds a link between two nodes for a specific hull and move flags.
---@param node1 AI_Node
---@param node2 AI_Node
---@param hull HULL? -- nil means all hulls
---@param move AI_MOVE_FLAGS
---@param enable boolean
function meta:SetLink(node1, node2, hull, move, enable)
    node1:SetLinkMove(node2, hull, move, enable)
end

---Removes the link between two nodes.
---@param node1 AI_Node
---@param node2 AI_Node
function meta:RemoveLink(node1, node2)
    node1:RemoveLink(node2)
end