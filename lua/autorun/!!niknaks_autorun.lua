-- Copyright © 2022-2072, Nak, https://steamcommunity.com/id/Nak2/
-- All Rights Reserved. Not allowed to be reuploaded.

AddCSLuaFile()
-- Make sure to use the newest version of NikNaks.
local version = 0.07
if NikNaks and NikNaks.Version > version then return end

local format = string.format

NikNaks = {}
NikNaks.Version = version
NikNaks.Authors = {"Nak"}
MsgN("Loading NikNaks: " .. NikNaks.Version)

do
	local c = SERVER and Color(156, 241, 255, 200) or Color(255, 241, 122, 200)
	function NikNaks.Msg( ... )
		local a = {...}
		if #a < 1 then return end
		MsgC(c,"[NN] ", unpack(a), "\n")
	end
end

-- Handles files and adds them by using thethe file-name.
function AutoInclude( str )
	local path = str
	if string.find(str,"/") then
		path = string.GetFileFromFilename(str)
	end
	local _type = string.sub(path,0,3)
	if SERVER then
		if _type == "cl_" or _type == "sh_" then
			AddCSLuaFile(str)
		end
		if _type ~= "cl_" then
			return include(str)
		end
	elseif _type ~= "sv_" then
		return pcall(include, str)
	end
end

-- Handles a folder
function AutoIncludeFolder( str )
	for _,fil in ipairs(file.Find(str .. "/*.lua","LUA")) do
		AutoInclude(str .. "/" .. fil)
	end
end

-- For safty reasons, we're not using auto include folder. These are hardcoded.
AutoInclude("niknaks/modules/sh_enums.lua")
AutoInclude("niknaks/modules/sh_util_extended.lua")
AutoInclude("niknaks/modules/sh_file_extended.lua")
AutoInclude("niknaks/modules/sh_color_extended.lua")
AutoInclude("niknaks/modules/sh_model_extended.lua")
AutoInclude("niknaks/modules/sh_bytebuffer.lua")
AutoInclude("niknaks/modules/sh_staticprops.lua")
AutoInclude("niknaks/modules/sh_bsp_module.lua")
AutoInclude("niknaks/modules/sh_pathfind_module.lua")
AutoInclude("niknaks/modules/sh_ain_module.lua")
AutoInclude("niknaks/modules/sh_nnn_areas.lua")
AutoInclude("niknaks/modules/sh_nnn_points.lua")
AutoInclude("niknaks/modules/sh_nnn_module.lua")
AutoInclude("niknaks/modules/sh_nnn_pathfinder.lua")

AutoInclude("niknaks/framework/sh_localbsp.lua")
AutoInclude("niknaks/framework/sh_epath.lua")

--AutoIncludeFolder("niknaks/modules")
--AutoIncludeFolder("niknaks/framework")