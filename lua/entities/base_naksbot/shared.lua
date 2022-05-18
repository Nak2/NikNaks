--[[
	Same as nextbot, but has build in LPathFollower support and a few features
]]
NikNaks()
AddCSLuaFile()

ENT.Base = "base_nextbot"

ENT.RenderGroup		= RENDERGROUP_OPAQUE

ENT.Spawnable = false
ENT.AdminOnly = false

AutoInclude("sh_coroutine.lua")
AutoInclude("sh_overlay.lua") 	-- Allows the NPC to have another model on the client.
AutoInclude("sv_targetnsound.lua")
AutoInclude("sv_basicmoves.lua")	-- Basic movement functions
AutoInclude("sv_movecalls.lua")	-- Basic functions being called when moving. Used for animations.
AutoInclude("sv_path.lua")			-- Basic pathfind functions