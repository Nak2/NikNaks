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
