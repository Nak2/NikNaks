--- HULL enums exist server-side, so we need to define them here.
---@enum HULL
NikNaks.HULL = {
    HUMAN           = 0, -- 30w, 73t     // Combine, Stalker, Zombie...
    SMALL_CENTERED  = 1, -- 40w, 40t     // Scanner
    WIDE_HUMAN      = 2, -- ?           // Vortigaunt
    TINY            = 3, -- 24w, 24t     // Headcrab
    WIDE_SHORT      = 4, -- ?           // Bullsquid
    MEDIUM          = 5, -- 36w, 65t     // Cremator
    TINY_CENTERED   = 6, -- 16w, 8t      // Manhack 
    LARGE           = 7, -- 80w, 100t    // Antlion Guard
    LARGE_CENTERED  = 8, -- ?           // Mortar Synth / Strider
    MEDIUM_TALL     = 9, -- 36w, 100t    // Hunter
}
NikNaks.NUM_HULLS = 10

-- Errors
---@enum BSP_ERROR
NikNaks.BSP_ERROR = {
    FILECANTOPEN  = 0, -- This error is thrown when the file can't be opened.
    NOT_BSP       = 1, -- This error is thrown when the file isn't a BSP-file.
    TOO_NEW       = 2, -- This error is thrown when the file is too new.
    FILENOTFOUND  = 3, -- This error is thrown when the file isn't found.
}

-- AI Nodes
---@enum NODE_TYPE
NikNaks.NODE_TYPE = {
    INVALID = -1, -- Any nodes not matching these
    ANY     = 0,
    DELETED = 1,  -- Internal in hammer?
    GROUND  = 2,
    AIR     = 3,
    CLIMB   = 4,
}

-- AI movement
---@enum PATHTYPE
NikNaks.PATHTYPE = {
    NONE   = -1, -- In case there are no path-options on the map
    AIN    = 0,
    NAV    = 1,
    NIKNAV = 2,
}

---@enum PATHMOVETYPE
NikNaks.PATHMOVETYPE = {
    GROUND = 0,
    FLY    = 1,
}
