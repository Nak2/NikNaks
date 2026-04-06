NikNaks.Path.AI = NikNaks.Path.AI or {}

local NodeClasses = {
    ["info_node"]          = true,
    ["info_node_air"]      = true,
    ["info_node_hint"]     = true,
    ["info_hint"]          = true,
    ["info_node_climb"]    = true,
    ["info_node_air_hint"] = true,
}

---@enum AI_InfoNodeType
NikNaks.Path.AI.HintTypes = {
    None = 0,                         -- No hinttype detected.
    Window = 2,                       -- Used with info_hint. Face the window.
    ActBusy = 12,                     -- Used with info_node_hint. Act busy.
    VisuallyInteresting = 13,         -- Used with info_hint. Will mark the area interesting. NPCs will aim at it.
    VisuallyInterestingNoAim = 14,    -- Used with info_hint. Will mark the area interesting. NPCs will not aim at it.
    InhibitCombineMine = 15,          -- Used with info_hint. Inhibits combine mines within 15 feet.
    VisuallyInterestingStealth = 16,  -- Causes Alyx to go into stealth "readiness".
    CrouchCoverMedium = 100,          -- Used with info_node_hint. Crouch cover medium (64 units).
    CrouchCoverLow = 101,             -- Used with info_node_hint. Crouch cover low (40 units).
    WasteScannerSpawn = 102,          -- No info
    AntlionBurrowPoint = 400,         -- Antlions will burrow in or out of this point.
    ThumperFleePoint = 401,           -- Antlions will use this hint to flee towards when they are forced back by a thumper.
    HeadcrabBurrowPoint = 450,        -- Headcrabs will burrow in or out of this point.
    HeadcrabExitPotPoint = 451,       -- Todo
    CrowFlyToPoint = 700,             -- Crows will fly to this point
    FollowerWaitPoint = 900,          -- Followers will wait at this point.
    OverrideJumpPermission = 901,     -- NPCs will jump from this node to another sharing the same override.
    PlayerSquadTransitionPoint = 902, -- An NPC will teleport to one of these hints when its outsidetransition input is triggered
    NPCExitPoint = 903,               -- Part of ActBusy hint. NPCs will use this node to leave the area.
    StriderNode = 904,                -- Striders will use this hint to determine where to walk.
    PlayerAllyPushAway = 950,         -- Allies will try to use this node when moving away
    HL1WorldMachinery = 1000,         -- Legacy support. Used in HL1 for monster_houndeye to show curious animations at this node when IDLE.
    HL1WorldBlinkingLight = 1001,     -- Legacy support. Used in HL1 for monster_houndeye to show curious animations at this node when IDLE.
    HL1WorldHumanBlood = 1002,        -- Todo
    HL1WorldAlienBlood = 1003,        -- Todo
    Obsolete = 1004,                  -- Obsolete (Not part of valves)
    Unknown = -1                      -- Unknown hint type.
}

local hinttypeLookup = {}
for k, v in pairs(NikNaks.Path.AI.HintTypes) do
    hinttypeLookup[v] = k
end

---@class AI_DynamicLink
---@field pos Vector
---@field startNode integer
---@field endNode integer

---@class AI_LookupLink
---@field nodeId integer
---@field nodeIndex integer
---@field entities BSPEntity[]
---@field dynamicLinks AI_DynamicLink[]

---@type table<integer, AI_LookupLink>|nil
local lookupLinks = nil

local function isUseful(data)
    local n = #data.entities
    if(n == 0 and #data.dynamicLinks == 0) then return false end
    if(n > 1) then return true end

    local e = data.entities[1]
    return e.classname ~= "info_node" and e.classname ~= "info_node_air"
end

--- Builds and caches a lookup table mapping AIN node indices to their associated entities and dynamic links.
--- The node index is hardcoded into the BSP, and maps to a nodeid which is used to find the relevant entities.
--- Returns a table of LookupLinks keyed by nodeIndex, and a list of link controllers.
---@return table<integer, AI_LookupLink>
function NikNaks.Path.AI.GetLookupTable()
    if lookupLinks then return lookupLinks end
    local tempLookupLinks = {}

    local entities = NikNaks.CurrentMap:GetEntities()
    local function getEntityLink(nodeId)
        local entityLink = tempLookupLinks[nodeId]
        if entityLink then return entityLink end
        entityLink = {
            nodeId       = nodeId,
            entities     = {},
            dynamicLinks = {},
        }
        tempLookupLinks[nodeId] = entityLink
        return entityLink
    end

    -- First pass: build nodeIndex -> nodeid, collect entities and dynamic links
    local lookUpTab = {}
    local nodeCount = 0
    for i = 0, #entities do
        local ent = entities[i]
        local nodeid, class = ent.nodeid --[[@as integer?]], ent.classname --[[@as string?]]
        if not nodeid or not class then continue end

        if NodeClasses[class] then
            lookUpTab[nodeCount] = nodeid -- nodeIndex -> nodeid
            table.insert(getEntityLink(nodeid).entities, ent)
            nodeCount = nodeCount + 1

        elseif class == "info_node_link" then
            local startNode = ent.StartNode
            local endNode   = ent.EndNode
            if startNode and endNode then
                local dynamicLink = {
                    pos       = ent.origin,
                    startNode = startNode,
                    endNode   = endNode,
                }
                table.insert(getEntityLink(startNode).dynamicLinks, dynamicLink)
                table.insert(getEntityLink(endNode).dynamicLinks, dynamicLink)
            end
        end
    end

    -- Second pass: invert lookUpTab to nodeid -> nodeIndex, patch onto each link
    lookupLinks = {}
    for nodeIndex, nodeid in pairs(lookUpTab) do
        -- Toss out map-entities that hold no data
        local data = tempLookupLinks[nodeid]
        if not data or not isUseful(data) then continue end
        lookupLinks[nodeIndex] = data
        data.nodeIndex = nodeIndex
    end

    return lookupLinks
end

local obsoleteNotes = {
    [103] = true,
    [104] = true,
    [105] = true,
    [106] = true,
    [500] = true,
    [501] = true,
    [701] = true,
}

---Returns the hinttype for the given BSPEntity ( If any )
---@param BSPEntity BSPEntity
---@return AI_InfoNodeType
function NikNaks.Path.AI.GetHintType(BSPEntity)
    local type = BSPEntity.hinttype --[[@as integer?]]
    return type == nil and NikNaks.Path.AI.HintTypes.None or
        obsoleteNotes[type] and NikNaks.Path.AI.HintTypes.Obsolete or
        hinttypeLookup[type] or NikNaks.Path.AI.HintTypes.Unknown
end
