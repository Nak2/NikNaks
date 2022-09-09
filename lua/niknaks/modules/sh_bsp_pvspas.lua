-- Copyright © 2022-2072, Nak, https://steamcommunity.com/id/Nak2/
-- All Rights Reserved. Not allowed to be reuploaded.
-- License: https://github.com/Nak2/NikNaks/blob/main/LICENSE

local obj_tostring = "BSP %s"
local format = string.format

local meta = NikNaks.__metatables["BSP"]
local meta_leaf = NikNaks.__metatables["BSP Leaf"]

--[[The data is stored as an array of bit-vectors; for each cluster, a list of which other clusters are visible 
	from it are stored as individual bits (1 if visible, 0 if occluded) in an array, with the nth bit position 
	corresponding to the nth cluster. ]]
local function getClusters( vis, offset, PVS )
	local v = offset
	local pvs_buffer = vis._bytebuff
	local num_clusters = vis.num_clusters
	local c = 0
	while c <= num_clusters do
		if pvs_buffer[v] == 0 then
			v = v + 1
			c = c + 8 * pvs_buffer[v]
		else
			local b = 1
			while b ~= 0 do
				if bit.band( pvs_buffer[v], b ) ~= 0 then
					PVS[c] = true
				end
				b = bit.band(b * 2, 0xFF)
				c = c + 1
			end
		end
		v = v + 1
	end
end

--- PVS ( Potentially Visible Set )
do
	---@class PVSObject
	local meta_pvs = {}
	meta_pvs.__index = meta_pvs
	meta_pvs.__tostring = function(self) return format( obj_tostring, "PVS" ) end
	meta_pvs.MetaName = "BSP PVS"
	NikNaks.__metatables["BSP PVS"] = meta_pvs

	local DVIS_PVS = 1

	---Creates a new empty PVS-object.
	---@return PVSObject
	function meta:CreatePVS()
		local t = {}
		setmetatable( t, meta_pvs )
		return t
	end

	---Uses the given ( or creates a new PVS-object ) and adds the position to it.
	---@param position Vector
	---@param PVSObject? PVS
	---@return PVSObject
	function meta:PVSForOrigin( position, PVS )
		if not PVS then
			PVS = {}
			setmetatable( PVS, meta_pvs )
		end
		PVS.__map = self
		local cluster = self:ClusterFromPoint( position )
		if cluster < 0 then return PVS end -- Empty cluster position.
		local vis = self:GetVisibility()
		local visofs = vis[ cluster ][ DVIS_PVS ]
		getClusters( vis, visofs, PVS )
		return PVS
	end

	--Returns true if the two positions are in same PVS.
	---@param position Vector
	---@param position2 Vector
	---@return boolean
	function meta:PVSCheck( position, position2 )
		local PVS = self:PVSForOrigin( position )
		local cluster = self:ClusterFromPoint( position2 )
		return PVS[cluster] or false
	end


	---Adds the position to PVS
	---@param position Vector
	---@return self
	function meta_pvs:AddPVS( position )
		self.__map:PVSForOrigin( position, self )
		return self
	end

	---Removes the position from PVS
	---@param position Vector
	---@return self
	function meta_pvs:RemovePVS( position )
		for id, vis in pairs( self.__map:PVSForOrigin( position ) ) do
			if id == "__map" then continue end
			self[id] = nil
		end
		return self
	end

	---Removes the leaf from PVS
	---@param leaf LeafObject
	---@return self
	function meta_pvs:RemoveLeaf( leaf )
		self[leaf.cluster] = nil
		return self
	end

	-- Returns true if the position is visible in the PVS
	---@param position Vector
	---@return boolean
	function meta_pvs:TestPosition( position )
		local cluster = self.__map:ClusterFromPoint( position )
		return self[cluster] or false
	end

	---Create PVS from Leaf
	---@return PVSObject
	function meta_leaf:CreatePVS()
		local PVS = {}
		setmetatable( PVS, meta_pvs )
		if self.cluster < 0 then return PVS end -- Leaf invalid. Return empty PVS.
		local vis = self.__map:GetVisibility()
		local visofs = vis[ self.cluster ][ DVIS_PVS ]
		getClusters( vis, visofs, PVS )
		return PVS
	end

	---Returns a list of leafs within this PVS. Note: This is a bit slow.
	function meta_pvs:GetLeafs()
		local leafs = self.__map:GetLeafs()
		local t = {}
		local n = 1
		for i = 1, #leafs do
			local leaf = leafs[i]
			if leaf.cluster < 0 then continue end -- Outside the map.
			if not self[leaf.cluster] then continue end
			t[n] = leaf
			n = n + 1
		end
		return t
	end

	---Returns true if the PVS has the given leaf
	---@param leaf LeafObject
	---@return boolean
	function meta_pvs:HasLeaf( leaf )
		if leaf.cluster < 0 then return false end
		return self[leaf.cluster]
	end
end

-- PAS
do
	---@class PASObject
	local meta_pas = {}
	meta_pas.__index = meta_pas
	meta_pas.__tostring = function(self) return format( obj_tostring, "PAS" ) end
	meta_pas.MetaName = "BSP PAS"
	NikNaks.__metatables["BSP PAS"] = meta_pas
	local DVIS_PAS = 2

	---Creates a new empty PAS-object.
	---@return PASObject
	function meta:CreatePAS()
		local t = {}
		setmetatable( t, meta_pas )
		return t
	end

	---Uses the given ( or creates a new PAS-object ) and adds the position to it.
	---@param position Vector
	---@param PASObject? PAS
	---@return PASObject
	function meta:PASForOrigin( position, PAS )
		if not PAS then
			PAS = {}
			setmetatable( PAS, meta_pas )
		end
		PAS.__map = self
		local cluster = self:ClusterFromPoint( position )
		local vis = self:GetVisibility()
		if cluster < 0 then return end -- err
		local visofs = vis[ cluster ][ DVIS_PAS ];
		getClusters( vis, visofs, PAS )
		return PAS
	end

	---Returns true if the two positions are in same PAS
	---@param position Vector
	---@param position2 Vector
	---@return boolean
	function meta:PASCheck( position, position2 )
		local PAS = self:PASForOrigin( position )
		return PAS[self:ClusterFromPoint( position2 )] or false
	end

	---Adds the position to PAS
	---@param position Vector
	---@return PASObject self
	function meta_pas:AddPAS( position )
		self.__map:PASForOrigin( position, self )
		return self
	end

	---Removes the position from PAS
	---@param position Vector
	---@return PASObject self
	function meta_pas:RemovePAS( position )
		for id, vis in pairs( self.__map:PASForOrigin( position ) ) do
			if id == "__map" then continue end
			self[id] = nil
		end
		return self
	end

		---Removes the leaf from PVS
	---@param leaf LeafObject
	---@return PASObject self
	function meta_pas:RemoveLeaf( leaf )
		self[leaf.cluster] = nil
		return self
	end

	---Returns true if the position is visible in the PAS
	---@param position Vector
	---@return boolean
	function meta_pas:TestPosition( position )
		local cluster = self.__map:ClusterFromPoint( position )
		return self[cluster] or false
	end

	---Create PAS from Leaf
	---@return PASObject
	function meta_leaf:CreatePAS()
		local PAS = {}
		setmetatable( PAS, meta_pas )
		if self.cluster < 0 then return PAS end -- Leaf invalid. Return empty PVS.
		local vis = self.__map:GetVisibility()
		local visofs = vis[ self.cluster ][ DVIS_PAS ]
		getClusters( vis, visofs, PAS )
		return PAS
	end

		---Returns true if the PAS has the given leaf
	---@param leaf LeafObject
	---@return boolean
	function meta_pas:HasLeaf( leaf )
		if leaf.cluster < 0 then return false end
		return self[leaf.cluster]
	end
end