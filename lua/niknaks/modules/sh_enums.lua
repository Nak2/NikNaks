-- Copyright © 2022-2072, Nak, https://steamcommunity.com/id/Nak2/
-- All Rights Reserved. Not allowed to be reuploaded.

-- Globals
vector_zero = Vector(0,0,0)
vector_unit = Vector(1,1,1)
vector_down = Vector(0,0,-1)

angle_up = vector_up:Angle()
angle_down = vector_down:Angle()

-- CAP
CAP_MOVE_GROUND								= 0x01 -- walk/run
CAP_MOVE_JUMP								= 0x02 -- jump/leap
CAP_MOVE_FLY								= 0x04 -- can fly, move all around
CAP_MOVE_CLIMB								= 0x08 -- climb ladders
--CAP_MOVE_SWIM / bits_BUILD_GIVEWAY?	= 0x10 -- navigate in water			// UNDONE - not yet implemented
--CAP_MOVE_CRAWL						= 0x20 -- crawl						// UNDONE - not yet implemented

-- Nodes
NODE_TYPE_INVALID 	=-1 -- Any nodes not matching these
NODE_TYPE_ANY 		= 0
NODE_TYPE_DELETED 	= 1 -- Internal in hammer?
NODE_TYPE_GROUND 	= 2
NODE_TYPE_AIR 		= 3
NODE_TYPE_CLIMB 	= 4
--NODE_TYPE_WATER 	= 5	-- Unused? I have no idea, since CAP_MOVE_SWIM seems unused and the fish use air nodes.

-- Hulls
HULL_HUMAN 			= 0	--	30w, 73t		// Combine, Stalker, Zombie...
HULL_SMALL_CENTERED = 1	--	40w, 40t		// Scanner
HULL_WIDE_HUMAN		= 2	--	?				// Vortigaunt
HULL_TINY			= 3	--	24w, 24t		// Headcrab
HULL_WIDE_SHORT		= 4	--	?				// Bullsquid
HULL_MEDIUM			= 5	--	36w, 65t		// Cremator
HULL_TINY_CENTERED	= 6	--	16w, 8t			// Manhack 
HULL_LARGE			= 7	--	80w, 100t		// Antlion Guard
HULL_LARGE_CENTERED = 8	--	?				// Mortar Synth / Strider
HULL_MEDIUM_TALL	= 9	--	36w, 100t		// Hunter
NUM_HULLS			= 10
-- HULL_NONE		= 11	Used internal I think.

-- Errors
BSP_ERROR_FILECANTOPEN  = 0
BSP_ERROR_NOT_BSP 		= 1
BSP_ERROR_TOO_NEW 		= 2
BSP_ERROR_FILENOTFOUND 	= 3
AIN_ERROR_VERSIONNUM	= 4
AIN_ERROR_ZONEPATCH		= 5	-- This error is thrown when the AIN-parser repairs the data. It will still return the data successfully.
NNN_ERROR_NAVNOTFOUND	= 6
NNN_ERROR_BSPNOTFOUND	= 7
NNN_ERROR_FILECANTOPEN	= 8

-- naksbot
PATHTYPE_NONE=-1	-- In case there are no path-options on the map
PATHTYPE_AIN = 0
PATHTYPE_NAV = 1
PATHTYPE_NNV = 2

-- How the NPC should move
PATHMOVETYPE_GROUND = 0
PATHMOVETYPE_FLY 	= 1
