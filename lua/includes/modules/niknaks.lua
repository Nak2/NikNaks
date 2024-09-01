-- Copyright © 2022-2072, Nak, https://steamcommunity.com/id/Nak2/
-- All Rights Reserved. Not allowed to be reuploaded.

AddCSLuaFile()
-- Make sure to use the newest version of NikNaks.
local version = 0.53
if NikNaks and NikNaks.VERSION > version then return end

local file_Find, MsgC, unpack = file.Find, MsgC, unpack

NikNaks = {}
NikNaks.net = {}
NikNaks.VERSION = version
NikNaks.Version = version -- For backwards compatibility
NikNaks.AUTHORS = { "Nak", "Phatso" }
NikNaks.__metatables = {}

do
	---A simply Msg function for NikNaks
	---@param ... any
	function NikNaks.Msg( ... )
		local a = {...}
		if #a < 1 then return end
		MsgC(NikNaks.REALM_COLOR,"[NN] ", unpack(a), "\n")
	end
end

---Auto includes, runs and AddCSLuaFile files using their prefix.
---@param str string File path
---@return any ... Anything the file returns
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
		return include(str)
	end
end

---Auto includes, runs and AddCSLuaFile a folder with lua-files, by the files prefix.
---@param str string Folder path
function NikNaks.AutoIncludeFolder( str )
	local files = file_Find(str .. "/*.lua","LUA")
	if(files == nil) then return end
	for _,fil in ipairs(files) do
		NikNaks.AutoInclude(str .. "/" .. fil)
	end
end

--[[
	For safty reasons, we're won't use AutoIncludeFolder. These should be hardcoded.
]]

--- @class BSPObject
local meta = {}
meta.__index = meta
meta.__tostring = function( self ) return string.format( "BSP Map [ %s ]", self._mapfile ) end
meta.MetaName = "BSP"
NikNaks.__metatables["BSP"] = meta
NikNaks._Source = "niknak"

NikNaks.AutoInclude("niknaks/modules/sh_hooks.lua")
NikNaks.AutoInclude("niknaks/modules/sh_enums.lua")
NikNaks.AutoInclude("niknaks/modules/sh_util_extended.lua")
NikNaks.AutoInclude("niknaks/modules/sh_randomizer.lua")
NikNaks.AutoInclude("niknaks/modules/sh_linq_module.lua")
NikNaks.AutoInclude("niknaks/modules/sh_file_extended.lua")
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
NikNaks.AutoInclude("niknaks/modules/sh_bsp_trace.lua")
NikNaks.AutoInclude("niknaks/modules/sh_soundModule.lua")
NikNaks.AutoInclude("niknaks/modules/sh_datapackage.lua")

NikNaks.AutoInclude("niknaks/framework/sh_localbsp.lua")

return NikNaks -- Doesn't work for require	:C