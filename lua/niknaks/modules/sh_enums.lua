-- Copyright © 2022-2072, Nak, https://steamcommunity.com/id/Nak2/
-- All Rights Reserved. Not allowed to be reuploaded.

-- Globals
NikNaks.vector_zero = Vector( 0, 0, 0 )
NikNaks.vector_down = Vector( 0, 0, -1 )

NikNaks.angle_up = vector_up:Angle()
NikNaks.angle_down = NikNaks.vector_down:Angle()

-- CAP
NikNaks.CAP_MOVE_GROUND								= 0x01 -- walk/run
NikNaks.CAP_MOVE_JUMP								= 0x02 -- jump/leap
NikNaks.CAP_MOVE_FLY								= 0x04 -- can fly, move all around
NikNaks.CAP_MOVE_CLIMB								= 0x08 -- climb ladders
--CAP_MOVE_SWIM / bits_BUILD_GIVEWAY?	= 0x10 -- navigate in water			// Removed by Valve: UNDONE - not yet implemented
--CAP_MOVE_CRAWL						= 0x20 -- crawl						// Removed by Valve: UNDONE - not yet implemented

-- Nodes
NikNaks.NODE_TYPE_INVALID 	=-1 -- Any nodes not matching these
NikNaks.NODE_TYPE_ANY 		= 0
NikNaks.NODE_TYPE_DELETED 	= 1 -- Internal in hammer?
NikNaks.NODE_TYPE_GROUND 	= 2
NikNaks.NODE_TYPE_AIR 		= 3
NikNaks.NODE_TYPE_CLIMB 	= 4
--NODE_TYPE_WATER 	= 5	-- Unused? I have no idea, since CAP_MOVE_SWIM seems unused and the fish use air nodes.

-- Hulls
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
-- HULL_NONE		= 11	Used internal I think.

-- Errors
NikNaks.BSP_ERROR_FILECANTOPEN  = 0
NikNaks.BSP_ERROR_NOT_BSP 		= 1
NikNaks.BSP_ERROR_TOO_NEW 		= 2
NikNaks.BSP_ERROR_FILENOTFOUND 	= 3
NikNaks.AIN_ERROR_VERSIONNUM	= 4
NikNaks.AIN_ERROR_ZONEPATCH		= 5	-- This error is thrown when the AIN-parser repairs the data. It will still return the data successfully.

-- naksbot
NikNaks.PATHTYPE_NONE=-1	-- In case there are no path-options on the map
NikNaks.PATHTYPE_AIN = 0
NikNaks.PATHTYPE_NAV = 1
NikNaks.PATHTYPE_NIKNAV = 2

-- How the NPC should move
NikNaks.PATHMOVETYPE_GROUND = 0
NikNaks.PATHMOVETYPE_FLY 	= 1
