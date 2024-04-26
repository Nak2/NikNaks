-- Copyright © 2022-2072, Nak, https://steamcommunity.com/id/Nak2/
-- All Rights Reserved. Not allowed to be reuploaded.
-- License: https://github.com/Nak2/NikNaks/blob/main/LICENSE

local obj_tostring = "BSP %s [ %s ]"
local format, clamp, min, max = string.format, math.Clamp, math.min, math.max

--- @class BSPObject
--- @field _dispFaceLeaf table<number, BSPFaceObject>
local meta = NikNaks.__metatables["BSP"]

--- @class BSPLeafObject
local meta_leaf = {}
meta_leaf.__index = meta_leaf
meta_leaf.__tostring = function( self ) return format( obj_tostring, "Leaf", self.__id ) end
meta_leaf.MetaName = "BSP Leaf"
NikNaks.__metatables["BSP Leaf"] = meta_leaf

local MAX_MAP_NODES = 65536
local TEST_EPSILON = 0.01
local FLT_EPSILON = 1.192092896e-07
local canGenerateParents = false

--- Generates parentNodes for nodes and leafs.
--- @param self BSPObject
--- @param nodeNum integer
--- @param parent integer
--- @param nodes MapNode[]
--- @param leafs BSPLeafObject[]
local function makeParents(self, nodeNum, parent, nodes, leafs, firstRun)
	if firstRun and not canGenerateParents then return end
	canGenerateParents = false

	nodes[nodeNum].parentNode = parent

	for i = 1, 2 do
		local j = nodes[nodeNum].children[i]
		if j < 0 then
			leafs[-j - 1].parentNode = nodeNum;
		else
			makeParents(self, j, nodeNum, nodes, leafs)
		end
	end
end

--- Returns a table of map nodes
--- @return MapNode[]
function meta:GetNodes()
	if self._node then return self._node end
	self._node = {}
	local data = self:GetLump( 5 )

	for i = 0, math.min( data:Size() / 256, MAX_MAP_NODES ) - 1 do
		--- @class MapNode
		--- @field children number[]
		--- @field planenum number
		--- @field plane BSPPlane
		--- @field mins Vector
		--- @field maxs Vector
		--- @field firstFace number
		--- @field numFaces number
		--- @field area number
		--- @field padding number
		--- @field parentNode number
		local t = {}
			t.planenum = data:ReadLong()
			t.plane = self:GetPlanes()[ t.planenum ]
			t.children = { data:ReadLong(), data:ReadLong() }
			t.mins = Vector( data:ReadShort(), data:ReadShort(), data:ReadShort() )
			t.maxs = Vector( data:ReadShort(), data:ReadShort(), data:ReadShort() )
			t.firstFace = data:ReadUShort()
			t.numFaces = data:ReadUShort()
			t.area = data:ReadShort()
			t.padding = data:ReadShort()
			t.parentNode = -1
		self._node[i] = t
	end

	self:ClearLump( 5 )

	canGenerateParents = true
	makeParents(self, 0, -1, self._node, self:GetLeafs(), true)
	canGenerateParents = false
	return self._node
end

--- Returns a table of map leafs.
--- @return BSPLeafObject[], number num_clusters
function meta:GetLeafs()
	if self._leafs then return self._leafs, self._leafs_num_clusters end

	--- @type BSPLeafObject[]
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

		--- @class BSPLeafObject
		--- @field mins Vector
		--- @field maxs Vector
		local t = {}
			t.contents = data:ReadLong() 	-- 32	32	4
			t.cluster = data:ReadShort() 	-- 16	48	6

			n = math.max( t.cluster + 1, n )

			local d = data:ReadUShort()
			t.area = bit.band( d, 0x1FF )		-- 16	64	8
			t.flags = bit.rshift( d, 9 )		-- 16	80	10
			
			t.mins = Vector( data:ReadShort(), data:ReadShort(), data:ReadShort() ) -- 16 x 3 ( 48 )	128		16
			t.maxs = Vector( data:ReadShort(), data:ReadShort(), data:ReadShort() ) -- 16 x 3 ( 48 )	176		22
			t.firstleafface 	= data:ReadUShort()	-- 16	192		24
			t.numleaffaces 		= data:ReadUShort()	-- 16	208		26
			t.firstleafbrush 	= data:ReadUShort()	-- 16	224		28
			t.numleafbrushes 	= data:ReadUShort()	-- 16	240		30
			t.leafWaterDataID 	= data:ReadShort()	-- 16	256		32
			t.__id = i
			t.__map = self
			t.parentNode = -1

			if t.leafWaterDataID > -1 then
				t.leafWaterData = self:GetLeafWaterData()[t.leafWaterDataID]
			end

			setmetatable( t, meta_leaf )

		self._leafs[i] = t
	end

	self._leafs_num_clusters = n
	self:ClearLump( 10 )

	canGenerateParents = true
	makeParents(self, 0, -1, self:GetNodes(), self._leafs, true)
	canGenerateParents = false

	return self._leafs, n
end

--- Returns a list of LeafWaterData. Holds the data of leaf nodes that are inside water.
--- @return BSPLeafWaterData[]
function meta:GetLeafWaterData()
	if self._pLeafWaterData then return self._pLeafWaterData end

	local data = self:GetLump( 36 )
	self._pLeafWaterData = {}

	for i = 0, data:Size() / 80 - 1 do
		--- @class BSPLeafWaterData
		--- @field surfaceZ number The height of the water surface
		--- @field minZ number The minimum height of the water
		--- @field surfaceTexInfoID number The texture info ID
		--- @field material IMaterial? The material of the water
		local t = {}
		t.surfaceZ = data:ReadFloat()
		t.minZ = data:ReadFloat()
		t.surfaceTexInfoID = data:ReadShort()
		local texInfo = self:GetTexInfo()[ t.surfaceTexInfoID ]
		if(texInfo ~= nil)then
			local texString = self:GetTexdataStringData()[ texInfo.texdata ]
			t.material = Material( texString )
		end
		data:Skip( 2 ) -- A short that is always 0x00
		self._pLeafWaterData[i] = t
	end

	self:ClearLump( 36 )
	return self._pLeafWaterData
end

--- Returns the number of leaf-clusters
--- @return number
function meta:GetLeafsNumClusters()
	local _, num_clusters = self:GetLeafs()
	return num_clusters
end

--- Returns the brushes in the given leaf.
--- @return BSPBrushObject[]
function meta_leaf:GetBrushes()
	if self._brushes then return self._brushes end

	--- @type BSPBrushObject[]
	self._brushes = {}
	local brush = self.__map:GetBrushes()
	local leafBrushes = self.__map:GetLeafBrushes()
	local c = self.firstleafbrush
	for i = 0, self.numleafbrushes do
		local f_id = leafBrushes[ i + c ]
		self._brushes[i + 1] = f_id
	end

	return self._brushes
end

local mat = Material( "vgui/menu_mode_border" )
local defaultColor = Color( 255, 0, 0, 255 )

--- A simple debug-render function that renders the leaf
--- @CLIENT
--- @param col Color
function meta_leaf:DebugRender( col )
	render.SetMaterial( mat )
	render.SetBlend( 0.8 )
	render.DrawBox( Vector( 0, 0, 0 ), Angle( 0, 0, 0 ), self.maxs, self.mins, col or defaultColor )
	render.SetBlend( 1 )
end

--- Returns the leaf index.
--- @return number
function meta_leaf:GetIndex()
	return self.__id or -1
end

--- Returns the leaf area.
--- @return number
function meta_leaf:GetArea()
	return self.area or -1
end

---In most cases, leafs within the skybox share the same value and are have the cluster id of 0.
-- However older Source versions doesn't have 3D skyboxes and untested on maps without 3D skybox.
--function meta_leaf:In3DSkyBox()
--	return self.cluster == 0
--end

--- Returns true if the leaf has the 3D sky within its PVS.
--- Note: Seems to be broken from EP2 and up.
--- @return boolean
function meta_leaf:HasSkyboxInPVS()
	return bit.band( self.flags, 0x1 ) ~= 0
end

--- Returns true if the leaf has the 3D sky within its PVS.
--- Note: Seems to be deprecated. Use Leaf:HasSkyboxInPVS() and BSP:HasSkyBox() instead.
--- @return boolean
--- @deprecated
function meta_leaf:Has2DSkyboxInPVS()
	return bit.band( self.flags, 0x4 ) ~= 0
end

--- Returns true if the leaf contains said content
--- @param CONTENTS CONTENTS
--- @return boolean
function meta_leaf:HasContents( CONTENTS )
	if CONTENTS == 0 then return self.contents == CONTENTS end
	return bit.band( self.contents, CONTENTS ) ~= 0
end

--- Returns the content flag the leaf has.
--- @return CONTENTS
function meta_leaf:GetContents()
	return self.contents
end

--- Returns a list of faces within this leaf. Starting at 1.
--- Note: A face can be in multiple leafs.
--- @param includeDisplacment boolean? # If true, it will include displacment faces. Note: this can be slow.
--- @return BSPFaceObject[]
function meta_leaf:GetFaces(includeDisplacment)
	if self._faces then return self._faces end

	--- @type BSPFaceObject[]
	self._faces = {}
	local faces = self.__map:GetFaces()
	local leafFace = self.__map:GetLeafFaces()
	local c = self.firstleafface

	for i = 0, self.numleaffaces do
		local f_id = leafFace[ i + c ]
		self._faces[i + 1] = faces[f_id]
	end

	if(includeDisplacment)then
		--- Displacments aren't included in leafs, we need to manually add them.
		if(not self.__map._dispFaceLeaf) then
			--- @type table<number, BSPFaceObject>
			self.__map._dispFaceLeaf = {}
			for key, value in pairs(self.__map:GetDisplacmentFaces()) do
				local vertexs = value:GetVertexs()
				if vertexs == nil or #vertexs ~= 4 then continue end -- Invalid displacment
				local leafs = self.__map:AABBInLeafs(0, vertexs[1], vertexs[3])
				for key, leaf in pairs(leafs) do
					if(not self.__map._dispFaceLeaf[leaf:GetIndex()]) then
						self.__map._dispFaceLeaf[leaf:GetIndex()] = {}
					end
					table.insert(self.__map._dispFaceLeaf[leaf:GetIndex()], value)
				end
			end
		end

		local dispFaces = self.__map._dispFaceLeaf[self:GetIndex()]
		if(dispFaces)then
			for key, value in pairs(dispFaces) do
				table.insert(self._faces, value)
			end
		end
	end

	return self._faces
end

--- Returns true if the leaf has water within.
--- @return boolean
function meta_leaf:HasWater()
	return self.leafWaterDataID > 0
end

--- Returns the water data, if any.
--- @return table?
function meta_leaf:GetWaterData()
	return self.leafWaterData
end

--- Returns the water MaxZ within the leaf.
--- @return number?
function meta_leaf:GetWaterMaxZ()
	return self.leafWaterData and self.leafWaterData.surfaceZ
end

--- Returns the water MinZ within the leaf.
--- @return number?
function meta_leaf:GetWaterMinZ()
	return self.leafWaterData and self.leafWaterData.minZ
end

--- Returns true if the leaf is outside the map.
--- @return boolean
function meta_leaf:IsOutsideMap()
	-- Locations outside the map are always cluster -1. However we check to see if the contnets is solid to be sure.
	return self.cluster == -1 and self.contents == 1
end

--- Returns the cluster-number for the leaf. Cluster numbers can be shared between multiple leafs. Note, SkyBox leafs the same cluster number.
--- @return number cluster # The cluster number of the leaf.
function meta_leaf:GetCluster()
	return self.cluster
end

--- Returns true if the position is within the given leaf. Do note leafs in older maps, sometimes overlap.
--- @param position Vector
--- @return boolean
function meta_leaf:IsPositionWithin( position )
	local l = self.__map:PointInLeaf(0, position)
	if not l then return false end
	return l:GetIndex() == self:GetIndex()
end

--- Returns a list of all leafs around the given leaf. Do note this is a rough estimate and may not be 100% accurate. Leafs are not always perfect cubes.
--- @param borderSize number? @The size of the border around the leaf.
--- @return BSPLeafObject[]
function meta_leaf:GetAdjacentLeafs(borderSize)
	local t, i, s = {}, 1, borderSize or 2
	for _, leaf in ipairs( self.__map:AABBInLeafs(0, self.mins, self.maxs, s) ) do
		if leaf == self then continue end
		t[i] = leaf
		i = i + 1
	end
	return t
end

--- Returns true if the leafs are adjacent to each other. Do note this is a rough estimate and may not be 100% accurate. Leafs are not always perfect cubes.
--- @return boolean
function meta_leaf:IsLeafAdjacent( leaf )
	for _, c_leaf in ipairs( self:GetAdjacentLeafs() ) do
		if c_leaf == leaf then return true end
	end
	return false
end

--- Roughly returns the distance from leaf to the given position.
--- @param position Vector
--- @return number
function meta_leaf:Distance( position )
	local cPos = Vector(clamp(position.x, self.mins.x, self.maxs.x),
						clamp(position.y, self.mins.y, self.maxs.y),
						clamp(position.z, self.mins.z, self.maxs.z))
	return cPos:Distance( position )
end

--- Roughly returns the distance from leaf to the given position.
--- @param position Vector
--- @return number
function meta_leaf:DistToSqr( position )
	local cPos = Vector(clamp(position.x, self.mins.x, self.maxs.x),
						clamp(position.y, self.mins.y, self.maxs.y),
						clamp(position.z, self.mins.z, self.maxs.z))
	return cPos:DistToSqr( position )
end

local planeMeta = NikNaks.__metatables["BSP Plane"]

--- Returns a list of planes, pointing into the leaf.
--- @return BSPPlane[]
function meta_leaf:GetBoundaryPlanes()
	local nodeIndex = self.parentNode
	local list = {}
	if not nodeIndex then return list end

	local child = -( self:GetIndex() + 1 )
	local nodes = self.__map:GetNodes()
	while ( nodeIndex >= 0 ) do
		local node = nodes[nodeIndex]
		local plane = node.plane
		if( node.children[1] == child ) then
			table.insert(list, plane)
		else
			table.insert(list, setmetatable({
				dist = -plane.dist,
				normal = -plane.normal,
				type = plane.type
			}, planeMeta))
		end

		child = nodeIndex
		nodeIndex = nodes[child].parentNode
	end
	return list
end

local function locateBoxLeaf( iNode, tab, mins, maxs, nodes, planes, leafs )
	local cornerMin, cornerMax = Vector(0,0,0), Vector(0,0,0)
	while iNode >= 0 do
		local node = nodes[ iNode ]
		local plane = planes[ node.planenum ]
		for i = 1, 3 do
			if( plane.normal[i] >= 0) then
				cornerMin[i] = mins[i]
				cornerMax[i] = maxs[i]
			else
				cornerMin[i] = maxs[i]
				cornerMax[i] = mins[i]
			end
		end
		if plane.normal:Dot(cornerMax) - plane.dist <= -TEST_EPSILON  then
			iNode = node.children[2]
		elseif plane.normal:Dot(cornerMin) - plane.dist >= TEST_EPSILON then
			iNode = node.children[1]
		else
			if not locateBoxLeaf(node.children[1], tab, mins, maxs, nodes, planes, leafs) then
				return false
			end
			return locateBoxLeaf(node.children[2], tab, mins, maxs, nodes, planes, leafs)
		end
	end
	tab[#tab + 1] = leafs[ -1 -iNode ]
	return true
end

--- Returns a list of leafs within the given two positions.
--- @param iNode? number # The node index to start from. Default is 0.
--- @param point Vector # The first point
--- @param point2 Vector # The second point
--- @param add? number # The size of the border around the AABB.
--- @return BSPLeafObject[]
function meta:AABBInLeafs( iNode, point, point2, add )
	add = add or 0
	local mins = Vector(min(point.x, point2.x) - add, min(point.y, point2.y) - add, min(point.z, point2.z) - add)
	local maxs = Vector(max(point.x, point2.x) + add, max(point.y, point2.y) + add, max(point.z, point2.z) + add)
	local tab = {}
	locateBoxLeaf(iNode or 0, tab, mins, maxs, self:GetNodes(), self:GetPlanes(), self:GetLeafs())
	return tab
end

---Returns true if the AABB has parts of the outside map within.
--- @param position Vector
--- @param position2 Vector
--- @return boolean
function meta:IsAABBOutsideMap( position, position2 )
	for _, leaf in pairs( self:AABBInLeafs( 0, position, position2 ) ) do
		if leaf:IsOutsideMap() then return true end
	end
	return false
end

local function locateSphereLeaf( iNode, tab, origin, radius, nodes, planes, leafs)
	while iNode >= 0 do
		local node = nodes[ iNode ]
		local plane = planes[ node.planenum ]
		if plane.normal:Dot(origin) + radius - plane.dist <= -TEST_EPSILON then
			iNode = node.children[2]
		elseif plane.normal:Dot(origin) - radius - plane.dist >= TEST_EPSILON then
			iNode = node.children[1]
		else
			if not locateSphereLeaf( node.children[1], tab, origin, radius, nodes, planes, leafs ) then
				return false
			end
			return locateSphereLeaf( node.children[2], tab, origin, radius, nodes, planes, leafs )
		end
	end
	tab[#tab + 1] = leafs[ -1 -iNode ]
	return true
end

--- Returns a list of leafs within the given sphere.
--- @param iNode number # The node index to start from. Default is 0.
--- @param origin Vector # The origin of the sphere
--- @param radius number # The radius of the sphere
--- @return BSPLeafObject[]
function meta:SphereInLeafs(iNode, origin, radius)
	local tab = {}
	locateSphereLeaf(iNode, tab, origin, radius, self:GetNodes(), self:GetPlanes(), self:GetLeafs())
	return tab
end

--- Returns true if the sphere has parts of the outside map within.
--- @param position Vector # The origin of the sphere
--- @param range number # The radius of the sphere
--- @return boolean
function meta:IsSphereOutsideMap( position, range )
	for _, leaf in pairs( self:SphereInLeafs( 0, position, range ) ) do
		if leaf:IsOutsideMap() then return true end
	end
	return false
end

--- Adds leafs intersecting between the two points.
--- @param self BSPObject
--- @param nodeIndex number
--- @param startFraction number
--- @param endFraction number
--- @param startPos Vector
--- @param endPos Vector
--- @param tab table
local function locateLineLeaf(self, nodeIndex, startFraction, endFraction, startPos, endPos, tab)
	if nodeIndex < 0 then
		local leaf = self:GetLeafs()[ -nodeIndex - 1]
		table.insert(tab, leaf)
	end

	local node = self:GetNodes()[nodeIndex]
	if not node then return end
	local plane = node.plane
	if not plane then return end

	local start_dist, end_dist = 0,0

	if plane.type == 0 then
		start_dist = startPos.x - plane.dist
		end_dist = endPos.x - plane.dist
	elseif plane.type == 1 then
		start_dist = startPos.y - plane.dist
		end_dist = endPos.y - plane.dist
	elseif plane.type == 2 then
		start_dist = startPos.z - plane.dist
		end_dist = endPos.z - plane.dist
	else
		start_dist = startPos:Dot( plane.normal ) - plane.dist
		end_dist = endPos:Dot( plane.normal ) - plane.dist
	end

	if start_dist >= 0 and end_dist >= 0 then
		locateLineLeaf(self, node.children[1], startFraction, endFraction, startPos, endPos, tab)
	elseif start_dist < 0 and end_dist < 0 then
		locateLineLeaf(self, node.children[2], startFraction, endFraction, startPos, endPos, tab)
	else
		local side_id, fraction_first, fraction_second, fraction_middle;
		if start_dist < end_dist then
			side_id = 2

			local inversed_distance  = 1 / ( start_dist - end_dist )
			fraction_first = ( start_dist + FLT_EPSILON ) * inversed_distance
			fraction_second = ( start_dist + FLT_EPSILON ) * inversed_distance
		elseif( end_dist < start_dist ) then
			side_id = 1

			local inversed_distance  = 1 / ( start_dist - end_dist )
			fraction_first = ( start_dist + FLT_EPSILON ) * inversed_distance
			fraction_second = ( start_dist - FLT_EPSILON ) * inversed_distance
		else
			side_id = 1
			fraction_first = 1
			fraction_second = 0
		end

		if fraction_first < 0 then 
			fraction_first = 0
		elseif fraction_first > 1 then
			fraction_first = 1
		end

		if fraction_second < 0 then 
			fraction_second = 0
		elseif fraction_second > 1 then
			fraction_second = 1
		end

		fraction_middle = startFraction + ( endFraction - startFraction ) * fraction_first
		local middle = startPos + fraction_first * ( endPos - startPos )

		locateLineLeaf( self, node.children[side_id], startFraction, fraction_middle, startPos, middle, tab)

		fraction_middle = startFraction + ( endFraction - startFraction ) * fraction_second
		middle = startPos + fraction_second * ( endPos - startPos )
		side_id = (side_id == 1) and 2 or 1
		locateLineLeaf( self, node.children[side_id], fraction_middle, endFraction, middle, endPos, tab)
	end
end

--- Returns a list of leafs between startPos and endPos.
--- @param iNode number # The node index to start from. Default is 0.
--- @param startPos Vector # The start position
--- @param endPos Vector # The end position
--- @return BSPLeafObject[]
function meta:LineInLeafs(iNode, startPos, endPos)
	local tab = {}
	locateLineLeaf(self, iNode or 0, 0, 1, startPos, endPos, tab)
	return tab
end

--- Returns true if the line has parts of the outside map within.
--- @param startPos Vector # The start position
--- @param endPos Vector # The end position
--- @return boolean
function meta:IsLineOutsideMap( startPos, endPos)
	for _, leaf in pairs( self:LineInLeafs( 0, startPos, endPos ) ) do
		if leaf:IsOutsideMap() then return true end
	end
	return false
end

--- Returns roughtly the leafs maximum boundary
--- @return Vector
function meta_leaf:OBBMaxs()
	return self.maxs
end

--- Returns roughtly the leafs minimums boundary
--- @return Vector
function meta_leaf:OBBMins()
	return self.mins
end

--- Returns roughtly the leafs center.
--- @return Vector
function meta_leaf:GetPos()
	return (self.mins + self.maxs) / 2
end