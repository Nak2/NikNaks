-- Copyright © 2022-2072, Nak, https://steamcommunity.com/id/Nak2/
-- All Rights Reserved. Not allowed to be reuploaded.

AddCSLuaFile()
-- Make sure to use the newest version of NikNaks.
local version = 0.36
if NikNaks and NikNaks.Version > version then return end

local file_Find, MsgC, unpack, rawget = file.Find, MsgC, unpack, rawget

NikNaks = {}
NikNaks.net = {}
NikNaks.Version = version
NikNaks.Authors = "Nak"
MsgN("Loading NikNaks: " .. NikNaks.Version)
NikNaks.__metatables = {}

do
	---A simply Msg function for NikNaks
	function NikNaks.Msg( ... )
		local a = {...}
		if #a < 1 then return end
		MsgC(NikNaks.REALM_COLOR,"[NN] ", unpack(a), "\n")
	end
end

---Auto includes, runs and AddCSLuaFile files using their prefix.
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

---Autp includes, runs and AddCSLuaFile a folder by the files prefix.
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
	local getfenv, setfenv, source = getfenv, setfenv, jit.util.funcinfo( NikNaks.AutoInclude )["source"]
	local NikNaks = NikNaks
	local function createEnv( tab, source )
		local t = {}
		setmetatable(t, { __index = function(k, v)
			return rawget(NikNaks, v) or tab[v]
		end,
		__newindex = function( t, k, v)
			rawset( _G, k, v )
		end})
		envs[ tab ] = t
		return t
	end

	-- Patches any tables with names that share _G
	--NikNaks._source = source:lower():match("addons/(.-)/")
	NikNaks._source = "niknak"
	local function using()
		local _env = getfenv( 2 )
		if _env ~= _GEnv then -- Make sure it isn't our env
			-- Create new env and apply it
			setfenv(2, envs[_env] or createEnv( _env, NikNaks._source ))
		else
			-- Ignore for now.
			-- error("Can't apply enviroment to self")
		end
	end

	setmetatable(NikNaks,{
		__call = function( _, ...) return using( ... ) end
	})
end

--[[
	For safty reasons, we're won't use AutoInclude or AutoIncludeFolder. These should be hardcoded.
]]

--- @class BSPObject
local meta = {}
meta.__index = meta
meta.__tostring = function( self ) return string.format( "BSP Map [ %s ]", self._mapfile ) end
meta.MetaName = "BSP"
NikNaks.__metatables["BSP"] = meta
NikNaks._Source = "niknak"

NikNaks.AutoInclude("niknaks/modules/sh_enums.lua")
NikNaks.AutoInclude("niknaks/modules/sh_util_extended.lua")
NikNaks.AutoInclude("niknaks/modules/sh_file_extended.lua")
NikNaks.AutoInclude("niknaks/modules/sh_timedelta.lua")
NikNaks.AutoInclude("niknaks/modules/sh_datetime.lua")
NikNaks.AutoInclude("niknaks/modules/sh_color_extended.lua")
NikNaks.AutoInclude("niknaks/modules/sh_model_extended.lua")
NikNaks.AutoInclude("niknaks/modules/sh_bitbuffer.lua")
NikNaks.AutoInclude("niknaks/modules/sh_bsp_module.lua")
NikNaks.AutoInclude("niknaks/modules/sh_bsp_entities.lua")
NikNaks.AutoInclude("niknaks/modules/sh_bsp_faces.lua")
NikNaks.AutoInclude("niknaks/modules/sh_bsp_leafs.lua")
NikNaks.AutoInclude("niknaks/modules/sh_bsp_brushes.lua")
NikNaks.AutoInclude("niknaks/modules/sh_bsp_pvspas.lua")
NikNaks.AutoInclude("niknaks/modules/sh_bsp_staticprops.lua")
NikNaks.AutoInclude("niknaks/modules/sh_pathfind_module.lua")
NikNaks.AutoInclude("niknaks/modules/sh_ain_module.lua")

NikNaks.AutoInclude("niknaks/framework/sh_localbsp.lua")
NikNaks.AutoInclude("niknaks/framework/sh_epath.lua")

-- Patch table to ref _G
do
	local g = _G
	for key, val in pairs( NikNaks ) do
		if not istable( val ) then continue end
		if not _G[key] then continue end
		--if not NikNaks._source:find("niknak") then continue end
		setmetatable(val, { __index = function(k, v)
			return rawget(k, v) or g[key][v]
		end})
	end
end

-- Post Init. This is a safety option, as using traces and other functions before InitPostEntity can cause crash.
if _NIKNAKS_POSTENTITY then
	NikNaks.PostInit = true
	timer.Simple(1, NikNaks._LoadPathOptions )
else
	hook.Add("NikNaks._LoadPathOptions", "wait", function()
		NikNaks.PostInit = true
		NikNaks._LoadPathOptions()
		hook.Remove("NikNaks._LoadPathOptions", "wait")
	end)
end
-- return NikNaks -- Doesn't work for require	:C
