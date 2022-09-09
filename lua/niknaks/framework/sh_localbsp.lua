-- Copyright © 2022-2072, Nak, https://steamcommunity.com/id/Nak2/
-- All Rights Reserved. Not allowed to be reuploaded.

-- Load the current map
local BSP = NikNaks.Map()
local NikNaks = NikNaks

NikNaks.CurrentMap = BSP

hook.Add( "PreDrawTranslucentRenderables", "NikNaks-FixEyePos", function()
	EyePos()
end )

-- Local PVS
NikNaks.PVS = {}
do
	local last_client, last_pvs
	local function calcPVS()
		local leaf, new = BSP:PointInLeafCache( 0, EyePos(), last_client )
		if not new then return last_pvs end
		last_client = leaf
		last_pvs = leaf:CreatePVS()
		return last_pvs
	end
	setmetatable(NikNaks.PVS, {
	__call = function(_, pos)
		if pos then
			return BSP:PVSForOrigin( pos )
		end
		if CLIENT then
			return calcPVS()
		end
	end})

	---Will return true if the position is within the current PVS.
	---@param position Vector
	---@param position2 Vector If nil, will be the clients EyePosition
	---@return boolean
	function NikNaks.PVS.IsPositionVisible( position, position2 )
		return calcPVS(position2):TestPosition( position )
	end
end

-- Local PAS
NikNaks.PAS = {}
do
	local last_client, last_pas
	local function calcPAS()
		local leaf, new = BSP:PointInLeafCache( 0, EyePos(), last_client )
		if not new then return last_pas end
		last_client = leaf
		last_pas = leaf:CreatePVS()
		return last_pas
	end
	setmetatable(NikNaks.PAS, {
	__call = function(_, pos)
		if pos then
			return BSP:PASForOrigin( pos )
		end
		if CLIENT then
			return calcPAS()
		end
	end})

	---Will return true if the position is within the current PAS.
	---@param position Vector
	---@param position2 Vector If nil, will be the clients EyePosition
	---@return boolean
	function NikNaks.PAS.IsPositionVisible( position, position2 )
		return calcPAS(position2):TestPosition( position )
	end
end



if SERVER then return end



