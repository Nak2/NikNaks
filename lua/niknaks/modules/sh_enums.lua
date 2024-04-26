-- Copyright © 2022-2072, Nak, https://steamcommunity.com/id/Nak2/
-- All Rights Reserved. Not allowed to be reuploaded.

-- Globals
NikNaks.vector_zero = Vector( 0, 0, 0 )
NikNaks.vector_down = Vector( 0, 0, -1 )

NikNaks.angle_up = vector_up:Angle()
NikNaks.angle_down = NikNaks.vector_down:Angle()

-- Cap move only exists server-side, so we need to define it here.
NikNaks.CAP_MOVE_GROUND								= 0x01 -- walk/run
NikNaks.CAP_MOVE_JUMP								= 0x02 -- jump/leap
NikNaks.CAP_MOVE_FLY								= 0x04 -- can fly, move all around
NikNaks.CAP_MOVE_CLIMB								= 0x08 -- climb ladders
--CAP_MOVE_SWIM / bits_BUILD_GIVEWAY?	= 0x10 -- navigate in water			// Removed by Valve: UNDONE - not yet implemented
--CAP_MOVE_CRAWL						= 0x20 -- crawl						// Removed by Valve: UNDONE - not yet implemented

-- AI Nodes
---@alias NODE_TYPE
---| `NikNaks.NODE_TYPE_INVALID`
---| `NikNaks.NODE_TYPE_ANY`
---| `NikNaks.NODE_TYPE_DELETED`
---| `NikNaks.NODE_TYPE_GROUND`
---| `NikNaks.NODE_TYPE_AIR`
---| `NikNaks.NODE_TYPE_CLIMB`

NikNaks.NODE_TYPE_INVALID 	=-1 -- Any nodes not matching these
NikNaks.NODE_TYPE_ANY 		= 0
NikNaks.NODE_TYPE_DELETED 	= 1 -- Internal in hammer?
NikNaks.NODE_TYPE_GROUND 	= 2
NikNaks.NODE_TYPE_AIR 		= 3
NikNaks.NODE_TYPE_CLIMB 	= 4
--NODE_TYPE_WATER 	= 5	-- Unused? I have no idea, since CAP_MOVE_SWIM seems unused and the fish use air nodes.

--- HULL enums excists server-side, so we need to define it here.
NikNaks.HULL_HUMAN 			= 0	--	30w, 73t		// Combine, Stalker, Zombie...
NikNaks.HULL_SMALL_CENTERED = 1	--	40w, 40t		// Scanner
NikNaks.HULL_WIDE_HUMAN		= 2	--	?				// Vortigaunt
NikNaks.HULL_TINY			= 3	--	24w, 24t		// Headcrab
NikNaks.HULL_WIDE_SHORT		= 4	--	?				// Bullsquid
NikNaks.HULL_MEDIUM			= 5	--	36w, 65t		// Cremator
NikNaks.HULL_TINY_CENTERED	= 6	--	16w, 8t			// Manhack 
NikNaks.HULL_LARGE			= 7	--	80w, 100t		// Antlion Guard
NikNaks.HULL_LARGE_CENTERED = 8	--	?				// Mortar Synth / Strider
NikNaks.HULL_MEDIUM_TALL	= 9	--	36w, 100t		// Hunter
NikNaks.NUM_HULLS			= 10
-- HULL_NONE				= 11 -- Max enum value

---@alias STATIC_PROP_FLAG
---| `NikNaks.STATIC_PROP_FLAG_FADES`
---| `NikNaks.STATIC_PROP_USE_LIGHTING_ORIGIN`
---| `NikNaks.STATIC_PROP_NO_DRAW`
---| `NikNaks.STATIC_PROP_IGNORE_NORMALS`
---| `NikNaks.STATIC_PROP_NO_SHADOW`
---| `NikNaks.STATIC_PROP_MARKED_FOR_FAST_REFLECTION`
---| `NikNaks.STATIC_PROP_NO_PER_VERTEX_LIGHTING`
---| `NikNaks.STATIC_PROP_NO_SELF_SHADOWING`
---| `NikNaks.STATIC_PROP_WC_MASK`

NikNaks.STATIC_PROP_FLAG_FADES = 1 -- Fades.
NikNaks.STATIC_PROP_USE_LIGHTING_ORIGIN = 2-- Use the lighting origin.
NikNaks.STATIC_PROP_NO_DRAW = 4 -- No draw.
NikNaks.STATIC_PROP_IGNORE_NORMALS = 8 -- Ignore normals.
NikNaks.STATIC_PROP_NO_SHADOW = 16 -- No shadow.
NikNaks.STATIC_PROP_MARKED_FOR_FAST_REFLECTION = 32 -- Marked for fast reflection.
NikNaks.STATIC_PROP_NO_PER_VERTEX_LIGHTING = 64 -- Disables per vertex lighting.
NikNaks.STATIC_PROP_NO_SELF_SHADOWING = 128 -- Disables self shadowing.
NikNaks.STATIC_PROP_WC_MASK = 220	-- All flags settable in hammer.

---@alias STATIC_PROP_FLAG_EX
---| `NikNaks.STATIC_PROP_FLAGS_EX_DISABLE_SHADOW_DEPTH` -- Do not render this prop into the CSM or flashlight shadow depth map.
---| `NikNaks.STATIC_PROP_FLAGS_EX_DISABLE_CSM` -- Disables cascaded shadow maps.
---| `NikNaks.STATIC_PROP_FLAGS_EX_ENABLE_LIGHT_BOUNCE` -- Enables light bounce in vrad.

NikNaks.STATIC_PROP_FLAGS_EX_DISABLE_SHADOW_DEPTH = 1 -- Do not render this prop into the CSM or flashlight shadow depth map.
NikNaks.STATIC_PROP_FLAGS_EX_DISABLE_CSM = 2 -- Disables cascaded shadow maps.
NikNaks.STATIC_PROP_FLAGS_EX_ENABLE_LIGHT_BOUNCE = 4 -- Enables light bounce in vrad.

-- Errors
---@alias BSP_ERROR
---| `NikNaks.BSP_ERROR_FILECANTOPEN`
---| `NikNaks.BSP_ERROR_NOT_BSP`
---| `NikNaks.BSP_ERROR_TOO_NEW`
---| `NikNaks.BSP_ERROR_FILENOTFOUND`

NikNaks.BSP_ERROR_FILECANTOPEN  = 0 -- This error is thrown when the file can't be opened.
NikNaks.BSP_ERROR_NOT_BSP 		= 1 -- This error is thrown when the file isn't a BSP-file.
NikNaks.BSP_ERROR_TOO_NEW 		= 2 -- This error is thrown when the file is too new.
NikNaks.BSP_ERROR_FILENOTFOUND 	= 3 -- This error is thrown when the file isn't found.

--[[ TODO: AI movement
NikNaks.PATHTYPE_NONE=-1	-- In case there are no path-options on the map
NikNaks.PATHTYPE_AIN = 0
NikNaks.PATHTYPE_NAV = 1
NikNaks.PATHTYPE_NIKNAV = 2

-- How the NPC should move
NikNaks.PATHMOVETYPE_GROUND = 0
NikNaks.PATHMOVETYPE_FLY 	= 1
]]