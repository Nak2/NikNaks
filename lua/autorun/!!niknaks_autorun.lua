-- Copyright © 2022-2072, Nak, https://steamcommunity.com/id/Nak2/
-- All Rights Reserved. Not allowed to be reuploaded.

AddCSLuaFile()
-- Make sure to use the newest version of NikNaks.
local version = 0.12
if NikNaks and NikNaks.Version > version then return end

local file_Find, MsgC, unpack, rawget = file.Find, MsgC, unpack, rawget

NikNaks = {}
NikNaks.net = {}
setmetatable(NikNaks,{
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

--[[
	TODO: For safty reasons, we're won't use AutoInclude in the final version. These should be hardcoded.
]]
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

-- A simple scope-script
do
	local g = _G
	local envs = {}
	local env = {}
	local getfenv, setfenv = getfenv, setfenv
	local NikNaks = NikNaks
	local function createEnv( tab )
		local t = {}
		setmetatable(t, { __index = function(k, v)
			return rawget(NikNaks, v) or tab[v]
		end,
		__newindex = function( t, k, v)
			rawset( _G, k ,v )
		end})
		envs[ tab ] = t
		return t
	end
	local _GEnv = createEnv( _G )
	-- Patches any tables with names that share _G
	function NikNaks.using()
		local _env = getfenv( 2 )
		if _env == g then
			setfenv(2, _GEnv)
		elseif _env ~= _GEnv then -- Make sure it isn't our env
			-- Create new env and apply it
			setfenv(2, envs[_env] or createEnv( _env ))
		else
			-- Ignore for now.
			-- error("Can't apply enviroment to self")
		end
	end
end

-- Patch table to ref _G
do
	local g = _G
	for key, val in pairs( NikNaks ) do
		if not istable( val ) then continue end
		if not _G[key] then continue end
		setmetatable(val, { __index = function(k, v)
			return rawget(k, v) or g[key][v]
		end})
	end
end

-- Post Init. This is a safety option, as using traces and other functions before can cause crash.
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