-- Copyright © 2022-2072, Nak, https://steamcommunity.com/id/Nak2/
-- All Rights Reserved. Not allowed to be reuploaded.

AddCSLuaFile()
-- Make sure to use the newest version of NikNaks.
local version = 0.08
if NikNaks and NikNaks.Version > version then return end

local file_Find, MsgC, unpack, rawget = file.Find, MsgC, unpack, rawget

NikNaks = {}
setmetatable(NikNaks,{
	__index = function(k, v) return rawget(NikNaks, v) or _G[v]	end
})
NikNaks.Version = version
NikNaks.Authors = "Nak"
MsgN("Loading NikNaks: " .. NikNaks.Version)

do
	function NikNaks.Msg( ... )
		local a = {...}
		if #a < 1 then return end
		MsgC(NikNaks.REALM_COLOR,"[NN] ", unpack(a), "\n")
	end
end

-- Handles files and adds them by using thethe file-name.
function NikNaks.AutoInclude( str )
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
function NikNaks.AutoIncludeFolder( str )
	for _,fil in ipairs(file_Find(str .. "/*.lua","LUA")) do
		NikNaks.AutoInclude(str .. "/" .. fil)
	end
end

-- A simple scope-script
do
	local g = _G
	local envs = {}
	local env = {}
	local getfenv, setfenv = getfenv, setfenv
	setmetatable(env, { __index = function(k, v)
		for i = 1, #envs do
			local val = rawget(envs[i], v)
			if val then return val end
		end
		return g[v]
	end })
	function NikNaks.using( ... )
		local tab = { ... }
		if getfenv( 2 ) == env then
			for i = 1, #tab do envs[#envs + 1] = tab[i] end
		elseif #tab > 0 then
			envs = tab
		else
			envs = { NikNaks }
		end
		setfenv(2, env)
	end
end

-- For safty reasons, we're not using auto include folder. These are hardcoded.
NikNaks.AutoInclude("niknaks/modules/sh_enums.lua")
NikNaks.AutoInclude("niknaks/modules/sh_util_extended.lua")
NikNaks.AutoInclude("niknaks/modules/sh_file_extended.lua")
NikNaks.AutoInclude("niknaks/modules/sh_color_extended.lua")
NikNaks.AutoInclude("niknaks/modules/sh_model_extended.lua")
NikNaks.AutoInclude("niknaks/modules/sh_bytebuffer.lua")
NikNaks.AutoInclude("niknaks/modules/sh_staticprops.lua")
NikNaks.AutoInclude("niknaks/modules/sh_bsp_module.lua")
NikNaks.AutoInclude("niknaks/modules/sh_pathfind_module.lua")
NikNaks.AutoInclude("niknaks/modules/sh_ain_module.lua")
NikNaks.AutoInclude("niknaks/modules/sh_niknav_areas.lua")
NikNaks.AutoInclude("niknaks/modules/sh_niknav_points.lua")
NikNaks.AutoInclude("niknaks/modules/sh_niknav_module.lua")
NikNaks.AutoInclude("niknaks/modules/sh_niknav_pathfinder.lua")

NikNaks.AutoInclude("niknaks/framework/sh_localbsp.lua")
NikNaks.AutoInclude("niknaks/framework/sh_epath.lua")

--AutoIncludeFolder("niknaks/modules")
--AutoIncludeFolder("niknaks/framework")