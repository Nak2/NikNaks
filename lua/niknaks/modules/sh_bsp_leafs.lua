-- Copyright © 2022-2072, Nak, https://steamcommunity.com/id/Nak2/
-- All Rights Reserved. Not allowed to be reuploaded.
-- License: https://github.com/Nak2/NikNaks/blob/main/LICENSE

local obj_tostring = "BSP %s [ %s ]"
local format = string.format

local meta = NikNaks.__metatables["BSP"]
local meta_leaf = {}
meta_leaf.__index = meta_leaf
meta_leaf.__tostring = function(self) return format( obj_tostring, "Leaf", self.__id ) end
meta_leaf.MetaName = "BSP Leaf"
NikNaks.__metatables["BSP Leaf"] = meta_leaf

local MAX_MAP_NODES = 65536
---Returns a table of map nodes
---@return table
function meta:GetNodes()
	if self._node then return self._node end
	self._node = {}
	local data = self:GetLump(5)
	
	for i = 0, math.min( data:Size() / 256, MAX_MAP_NODES ) - 1 do
		local t = {}
			t.planenum = data:ReadLong()
			t.children = {data:ReadLong(), data:ReadLong()}
			t.mins = Vector(data:ReadShort(), data:ReadShort(), data:ReadShort())
			t.maxs = Vector(data:ReadShort(), data:ReadShort(), data:ReadShort())
			t.firstFace = data:ReadUShort()
			t.numFaces = data:ReadUShort()
			t.area = data:ReadShort()
			t.padding = data:ReadShort()
		self._node[i] = t
	end
	self:ClearLump( 5 )
	return self._node
end

---Returns a table of map leafs.
---@return table
function meta:GetLeafs()
	if self._leafs then return self._leafs end
	self._leafs = {}
	local lumpversion = self:GetLumpVersion( 10 )
	local data = self:GetLump( 10 )
	local size = 240  -- version
	if lumpversion == 0 then
		size = size + 192 -- byte r, byte g,  byte b +  char expo
	end
	if self._version <= 19 or true then
		size = size + 16
	end
	local n = 0
	for i = 0, data:Size() / size - 1 do
		data:Seek( i * size )
		local t = {}
			t.contents = data:ReadLong() 	-- 32	32	4
			t.cluster = data:ReadShort() 	-- 16	48	6
			n = math.max( t.cluster + 1, n)
			local d = data:ReadUShort()
			t.area = bit.band(d, 0x1FF)		-- 16	64	8
			t.flags = bit.rshift(d, 9)		-- 16	80	10

			t.mins = Vector(data:ReadShort(), data:ReadShort(), data:ReadShort()) -- 16 x 3 ( 48 )	128		16
			t.maxs = Vector(data:ReadShort(), data:ReadShort(), data:ReadShort()) -- 16 x 3 ( 48 )	176		22
			t.firstleafface 	= data:ReadUShort()	-- 16	192		24
			t.numleaffaces 		= data:ReadUShort()	-- 16	208		26
			t.firstleafbrush 	= data:ReadUShort()	-- 16	224		28
			t.numleafbrushes 	= data:ReadUShort()	-- 16	240		30
			t.leafWaterDataID 	= data:ReadShort()	-- 16	256		32
			t.__id = i
			t.__map = self
			if t.leafWaterDataID > -1 then
				t.leafWaterData = self:GetLeafWaterData()[t.leafWaterDataID]
			end
			setmetatable(t, meta_leaf)
		self._leafs[i] = t
	end
	self._leafs.num_clusters = n
	self:ClearLump( 10 )
	return self._leafs
end

	---Returns a list of LeafWaterData. Holds the data of leaf nodes that are inside water.
---@return table
function meta:GetLeafWaterData( )
	if self._pLeafWaterData then return self._pLeafWaterData end
	local data = self:GetLump( 36 )
	self._pLeafWaterData = {}
	for i = 0, data:Size() / 80 - 1 do
		local t = {}
		t.surfaceZ = data:ReadFloat()
		t.minZ = data:ReadFloat()
		t.surfaceTexInfoID = data:ReadShort()
		data:Skip(2) -- A short that is always 0x00
		self._pLeafWaterData[i] = t
	end
	self:ClearLump( 36 )
	return self._pLeafWaterData
end

---Returns the number of leaf-clusters.
---@return number
function meta:GetLeafsNumClusters()
	return self:GetLeafs().num_clusters
end


local mat = Material("vgui/menu_mode_border")
local r = Color( 255, 0, 0, 255 )
---A simple debug-render function. Rendering the leaf.
---@CLIENT
function meta_leaf:DebugRender( col )
	render.SetMaterial(mat)
	render.SetBlend( 0.8 )
	render.DrawBox( Vector(0,0,0), Angle(0,0,0), self.maxs, self.mins, col or r )
	render.SetBlend( 1 )
end

---Returns the leaf index.
---@return number
function meta_leaf:GetIndex()
	return self.__id or -1
end

---Returns the leaf area
---@return number
function meta_leaf:GetArea()
	return self.area or -1
end

---In most cases, leafs within the skybox share the same value and are have the cluster id of 0.
-- However older Source versions doesn't have 3D skyboxes and untested on maps without 3D skybox.
--function meta_leaf:In3DSkyBox()
--	return self.cluster == 0
--end

---Returns true if the leaf has the 3D sky within its PVS.
---Note: Seems to be broken from EP2 and up.
---@return boolean
function meta_leaf:HasSkyboxInPVS()
	return bit.band( self.flags, 0x1 ) ~= 0
end

---Returns true if the leaf has the 3D sky within its PVS.
---Note: Seems to be deprecated. Use Leaf:HasSkyboxInPVS() and BSP:HasSkyBox() instead.
---@return boolean
function meta_leaf:Has2DSkyboxInPVS()
	return bit.band( self.flags, 0x4 ) ~= 0
end

---Returns true if the leaf has said content
---@return boolean
function meta_leaf:HasContents( CONTENTS )
	if CONTENTS == 0 then return self.contents == CONTENTS end
	return bit.band( self.contents, CONTENTS ) ~= 0
end

---Returns the content flag the leaf has.
---@return number
function meta_leaf:GetContents()
	return self.contents
end

---Returns a list of faces within this leaf. Starting at 1.
---Note: A face can be in multiple leafs.
---@return table
function meta_leaf:GetFaces()
	if self._faces then return self._faces end
	self._faces = {}
	local faces = self.__map:GetFaces()
	local leafFace = self.__map:GetLeafFaces()
	local c = self.firstleafface
	for i = 0, self.numleaffaces do
		local f_id = leafFace[ i + c ]
		self._faces[i + 1] = faces[f_id]
	end
	return self._faces
end

---Returns true if the leaf has water within.
---@return boolean
function meta_leaf:HasWater()
	return self.leafWaterDataID > 0
end

---Returns the water data, if any.
---@return table|nil
function meta_leaf:GetWaterData()
	return self.leafWaterData
end

---Returns the water MaxZ within the leaf.
---@return number|nil
function meta_leaf:GetWaterMaxZ()
	return self.leafWaterData and self.leafWaterData.surfaceZ
end

---Returns the water MinZ within the leaf.
---@return number|nil
function meta_leaf:GetWaterMinZ()
	return self.leafWaterData and self.leafWaterData.minZ
end

---Returns true if the leaf is outside the map.
---@return boolean
function meta_leaf:IsOutsideMap()
	-- Locations outside the map are always cluster -1. However we check to see if the contnets is solid to be sure.
	return self.cluster == -1 and self.contents == 1 
end

---Returns the cluster-number for the leaf. Cluster numbers can be shared between multiple leafs.
---@return number
function meta_leaf:GetCluster()
	return self.cluster
end