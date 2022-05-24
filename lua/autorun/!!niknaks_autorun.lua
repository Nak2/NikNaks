-- Copyright © 2022-2072, Nak, https://steamcommunity.com/id/Nak2/
-- All Rights Reserved. Not allowed to be reuploaded.

AddCSLuaFile()
-- Make sure to use the newest version of NikNaks.
local version = 0.08
if NikNaks and NikNaks.Version > version then return end

local file_Find, MsgC, unpack, rawget = file.Find, MsgC, unpack, rawget

NikNaks = {}
NikNaks.net = {}
setmetatable(NikNaks,{
	__index = function(k, v) return rawget(NikNaks, v) or _G[v]	end,
	__call = function( _, ...) return NikNaks.using( ... ) end
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
	local _type
	if path ~= "shared.lua" then
		_type = string.sub(path,0,3)
	else
		_type = "sh_"
	end
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
local env_gpatch
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
	end
	})
	-- Patches any tables with nakes that share _G
	function env_gpatch( tab )
		for key, val in pairs( tab ) do
			if type(val) ~= "table" then continue end
			if not _G[key] then continue end
			setmetatable(val, { __index = function(k, v)
				return rawget(k, v) or _G[key][v]
			end})
		end
	end
	function NikNaks.using( ... )
		local tab = { ... }
		if getfenv( 2 ) == env then
			for i = 1, #tab do 
				env_gpatch(tab[i])
				envs[#envs + 1] = tab[i]
			end
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

env_gpatch(NikNaks)

-- Post Init
NikNaks.PostInit = _NIKNAKS_POSTENTITY or false
if not NikNaks.PostInit then
	hook.Add("InitPostEntity","NikNaks_InitPostEntity", function()
		NikNaks.PostInit = true
		_NIKNAKS_POSTENTITY = true
		hook.Remove("InitPostEntity","NikNaks_InitPostEntity")
		timer.Simple(1, NikNaks._LoadPathOptions )
	end)
else
	timer.Simple(1, NikNaks._LoadPathOptions )
end