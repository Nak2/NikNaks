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
    NUM_HULLS       = 10
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

-- The type of the world-light.
---@enum LightEmissionType
NikNaks.LIGHTEMISSIONTYPE = {
    EMIT_SURFACE    = 0, --Light emitted from a brush surface/texture (e.g., glowing light-strips).
    EMIT_POINT      = 1, --An omnidirectional point source that radiates light in all directions.
    EMIT_SPOTLIGHT  = 2, --A directional cone of light with defined inner and outer beam angles.
    EMIT_SKYLIGHT   = 3, --Parallel light rays representing direct sunlight from the skybox.
    EMIT_QUAKELIGHT = 4, --Legacy linear-falloff light using original Quake engine attenuation logic.
    EMIT_SKYAMBIENT = 5 --Non-directional ambient filler light representing the sky's indirect glow.
}
