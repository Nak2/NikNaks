-- Copyright © 2022-2072, Nak, https://steamcommunity.com/id/Nak2/
-- All Rights Reserved. Not allowed to be reuploaded.

-- Load the current map
--- @type BSPObject
local BSP, BSP_ERR = NikNaks.Map()
local NikNaks = NikNaks

--- @type BSPObject
NikNaks.CurrentMap = BSP

if not BSP and BSP_ERR then
	if BSP_ERR == NikNaks.BSP_ERROR_FILECANTOPEN then
		ErrorNoHalt("NikNaks are unable to open the mapfile!")
	elseif BSP_ERR == NikNaks.BSP_ERROR_NOT_BSP then
		ErrorNoHalt("NikNaks can't read the mapfile (It isn't VBSP)!")
	elseif BSP_ERR == NikNaks.BSP_ERROR_TOO_NEW then
		ErrorNoHalt("NikNaks can't read the mapfile (Newer than v20)!")
	elseif BSP_ERR == NikNaks.BSP_ERROR_FILENOTFOUND then
		ErrorNoHalt("NikNaks can't read the mapfile (File not found)!")
	else
		ErrorNoHalt("NikNaks can't read the mapfile (Unknown)!")
	end
end