NikNaks.Path.AI = NikNaks.Path.AI or {}

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
---@field targetname string?
---@field pos Vector
---@field startNode integer
---@field endNode integer
---@field enabled boolean
---@field alwaysAllowClass? string
---@field invertedAllow boolean -- If true, the link will allow all classes except the one specified in alwaysAllowClass
---@field moveType AI_MOVE_FLAGS

---@class AI_LookupLink
---@field nodeId integer
---@field nodeIndex integer
---@field entities BSPEntity[]
---@field dynamicLinks AI_DynamicLink[]

---@class AI_Controller
---@field origin Vector
---@field mins Vector
---@field maxs Vector
---@field enabled boolean
---@field userairlinkedradius boolean
---@field alwaysAllowClass string?
---@field invertedAllow boolean -- If true, the controller will allow all classes except the one specified

---@class AI_Hint
---@field origin Vector
---@field hinttype integer
---@field nodeid integer
---@field nodeFOV number
---@field ignoreFacing integer
---@field minimumState integer
---@field maximumState integer
---@field targetNode integer
---@field spawnflags integer

---@type table<integer, AI_LookupLink>|nil
local lookupLinks = nil
---@type AI_Controller[]|nil
local controllers = nil
---@type AI_Hint[]|nil
local hints = nil

local function isUseful(data)
    local n = #data.entities
    if (n == 0 and #data.dynamicLinks == 0) then return false end
    if (n > 1) then return true end

    local e = data.entities[1]
    return e.classname ~= "info_node" and e.classname ~= "info_node_air"
end

local NodeClasses = {
    ["info_node"]          = true,
    ["info_node_air"]      = true,
    ["info_node_hint"]     = true,
    ["info_hint"]          = true,
    ["info_node_climb"]    = true,
    ["info_node_air_hint"] = true,
}

---@param dynamicLinks table<string, AI_DynamicLink>
---@param controlEntities table<string, AI_Controller>
local function AddEntityHooks(dynamicLinks, controlEntities)
    hook.Add("AcceptInput", "NikNaks.AI_DynamicLinkControl", function(ent, key, value)
        local name = ent:GetName()
        key = string.lower(key)
        if (dynamicLinks[name]) then
            local link = dynamicLinks[name]
            if key == "turnon" then
                link.enabled = true
            elseif key == "turnoff" then
                link.enabled = false
            end
        elseif controlEntities[name] then
            local control = controlEntities[name]
            if key == "turnon" then
                control.enabled = true
            elseif key == "turnoff" then
                control.enabled = false
            elseif key == "setallowed" then
                control.alwaysAllowClass = value
            elseif key == "setinverted" then
                control.invertedAllow = value == "1"
            end
        end
    end)
end

--- Builds and caches a lookup table mapping AIN node indices to their associated entities and dynamic links.
--- The node index is hardcoded into the BSP, and maps to a nodeid which is used to find the relevant entities.
--- Returns a table of LookupLinks keyed by nodeIndex, and a list of link controllers.
---@return table<integer, AI_LookupLink>
function NikNaks.Path.AI.GetLookupTable()
    if lookupLinks then return lookupLinks end
    local tempLookupLinks = {}

    local entities = NikNaks.CurrentMap:GetEntities()
    local maxKey = 0
    for key, _ in pairs(entities) do
        maxKey = math.max(key, maxKey)
    end

    local function getEntityLink(nodeId)
        if nodeId == nil then nodeId = -1 end
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
    local controlEntities = {}
    local allControllers = {}
    local allHints = {}
    local dynamicLinks = {}
    local hasEnts = false
    for i = 0, maxKey do
        local ent = entities[i]
        if not ent then continue end
        local class = ent.classname
        if not class then continue end
        local nodeid = ent.nodeid or -1

        if class == "info_hint" then
            -- info_hint is a world hint marker, not an AIN navigation node; collect separately
            allHints[#allHints + 1] = {
                origin       = ent.origin,
                hinttype     = ent.hinttype or 0,
                nodeid       = nodeid,
                nodeFOV      = ent.nodeFOV or 360,
                ignoreFacing = ent.IgnoreFacing or 0,
                minimumState = ent.MinimumState or 0,
                maximumState = ent.MaximumState or 3,
                targetNode   = ent.TargetNode or -1
            }
        elseif NodeClasses[class] then
            if nodeid ~= -1 then
                table.insert(getEntityLink(nodeid).entities, ent)
                lookUpTab[nodeCount] = nodeid -- nodeIndex -> nodeid
                nodeCount = nodeCount + 1
            end
        elseif class == "info_node_link" then
            local startNode = ent.StartNode
            local endNode   = ent.EndNode
            if startNode and endNode then
                local dynamicLink = {
                    pos              = ent.origin,
                    startNode        = startNode,
                    endNode          = endNode,
                    enabled          = ent.initialstate == 1,
                    moveType         = ent.linktype or 0,
                    alwaysAllowClass = ent.AllowUse,
                    invertedAllow    = ent.InvertAllow == 1,
                }
                table.insert(getEntityLink(startNode).dynamicLinks, dynamicLink)
                table.insert(getEntityLink(endNode).dynamicLinks, dynamicLink)
                if (ent.targetname) then
                    local dynamicLinkEntity = SERVER and ents.FindByName(ent.targetname)[1]
                    if dynamicLinkEntity then
                        -- If the entity exists, we need to check if it is enabled
                        dynamicLink.enabled = dynamicLinkEntity:GetInternalVariable("m_bDisabled") == 0
                    end
                    dynamicLinks[ent.targetname] = dynamicLink
                    hasEnts = true
                end
            end
        elseif class == "info_node_link_controller" then
            local controller = {
                origin = ent.origin,
                mins = Vector(ent.mins),
                maxs = Vector(ent.maxs),
                enabled = ent.initialstate == 1,
                userairlinkedradius = ent.UserAirLinkedRadius == 1,
                alwaysAllowClass = ent.AllowUse,
                invertedAllow = ent.InvertAllow == 1
            }
            allControllers[#allControllers + 1] = controller
            if (ent.targetname) then
                controlEntities[ent.targetname] = controller
                local controllerEntity = SERVER and ents.FindByName(ent.targetname)[1]
                if controllerEntity then
                    -- If the entity exists, we need to check if it is enabled
                    controller.enabled = controllerEntity:GetInternalVariable("m_bDisabled") == 0
                    controller.alwaysAllowClass = controllerEntity:GetInternalVariable("m_iClass")    -- This is a bit hacky, but it allows mapmakers to set the allowed class in hammer using the iClass variable of the entity, which is normally unused for this entity type
                    controller.invertedAllow = controllerEntity:GetInternalVariable("m_iClass2") ==
                    1                                                                                 -- Similarly, we can use iClass2 to set whether the allow is inverted
                end
                hasEnts = true
            end
        end
    end

    if (hasEnts) then
        AddEntityHooks(dynamicLinks, controlEntities)
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

    controllers = allControllers
    hints = allHints
    return lookupLinks
end

--- Returns the list of link controllers for the current map.
--- Ensures GetLookupTable() has been called first.
---@return AI_Controller[]
function NikNaks.Path.AI.GetControllers()
    if not controllers then NikNaks.Path.AI.GetLookupTable() end
    return controllers or {}
end

--- Returns the list of info_hint markers for the current map.
--- Ensures GetLookupTable() has been called first.
---@return AI_Hint[]
function NikNaks.Path.AI.GetHints()
    if not hints then NikNaks.Path.AI.GetLookupTable() end
    return hints or {}
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
---@return string
function NikNaks.Path.AI.GetHintType(BSPEntity)
    local type = BSPEntity.hinttype --[[@as integer?]]
    return type == nil and "None" or
        obsoleteNotes[type] and "Obsolete" or
        hinttypeLookup[type] or "Unknown"
end

---Returns the hinttype for the given BSPEntity ( If any )
---@param BSPEntity BSPEntity
---@return string
function NikNaks.Path.AI.GetHintName(BSPEntity)
    return hinttypeLookup[NikNaks.Path.AI.GetHintType(BSPEntity)] or "Unknown"
end
