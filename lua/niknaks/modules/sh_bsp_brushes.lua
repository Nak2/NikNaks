-- Copyright © 2022-2072, Nak, https://steamcommunity.com/id/Nak2/
-- All Rights Reserved. Not allowed to be reuploaded.
-- License: https://github.com/Nak2/NikNaks/blob/main/LICENSE

local obj_tostring = "BSP %s [ %s ]"
local format = string.format

--- @class BSPObject
local meta = NikNaks.__metatables["BSP"]

--- @class BrushObject
local meta_brush = {}
meta_brush.__index = meta_brush
meta_brush.__tostring = function( self ) return format( obj_tostring, "BSP Brush", self.__id ) end
meta_brush.MetaName = "BSP Brush"
NikNaks.__metatables["BSP Brush"] = meta_brush

local DIST_EPSILON = 0.03125
local MAX_MAP_BRUSHES = 8192
local MAX_MAP_BRUSHSIDES = 65536

--- Returns an array of the brush-data with brush-sides.
--- @return BrushObject[]
function meta:GetBrushes()
	if self._brushes then return self._brushes end

	self._brushes = {}

	local data = self:GetLump( 18 )
	for id = 1, math.min( data:Size() / 96, MAX_MAP_BRUSHES ) do
		--- @class BrushObject
		local t = {}
		local first = data:ReadLong()
		local num = data:ReadLong()
		t.contents = data:ReadLong()
		t.numsides = num
		--- @type BrushSideObject[]
		t.sides = {}
		t.__id = id
		t.__map = self

		local n = 1
		for i = first, first + num - 1 do
			t.sides[n] = self:GetBrushSides()[i]
			n = n + 1
		end

		self._brushes[id] = setmetatable( t, meta_brush )
	end

	self:ClearLump( 18 )
	return self._brushes
end

--- Returns an array of brushside-data.
--- @return BrushSideObject[]
function meta:GetBrushSides()
	if self._brushside then return self._brushside end

	self._brushside = {}

	local data = self:GetLump( 19 )
	local planes = self:GetPlanes()
	for i = 1, math.min( data:Size() / 64, MAX_MAP_BRUSHSIDES ) do
		--- @class BrushSideObject
		local t = {}
			t.plane = planes[ data:ReadUShort() ]
			t.texinfo = data:ReadShort()
			t.dispinfo = data:ReadShort()
			local q = data:ReadShort()
			t.bevel = bit.band( q, 0x1 ) == 1 -- Seems to be 1 if used for collision detection
			t.thin = bit.rshift( q, 8 ) == 1 -- For Portal 2 / Alien Swarm
		self._brushside[i - 1] = t
	end

	self:ClearLump( 19 )
	return self._brushside
end


function meta_brush:GetIndex()
	return self.__id or -1
end

--- Returns the content flag the brush has.
--- @return number
function meta_brush:GetContents()
	return self.contents
end

--- Returns true if the brush has said content
--- @param CONTENTS number
--- @return boolean
function meta_brush:HasContents( CONTENTS )
	if CONTENTS == 0 then return self.contents == CONTENTS end
	return bit.band( self.contents, CONTENTS ) ~= 0
end

-- Texture Stuff

--- Returns the TexInfo for the brush-side.
--- @param side number
--- @return table
function meta_brush:GetTexInfo( side )
	return self.__map:GetTexInfo()[self.sides[side].texinfo]
end

--- Returns the TexData for the brush-side.
--- @param side number
--- @return table
function meta_brush:GetTexData( side )
	return self.__map:GetTexData()[ self:GetTexInfo( side ).texdata]
end

--- Returns the texture for the brush-side.
--- @param side number
--- @return string
function meta_brush:GetTexture( side )
	local t = self:GetTexData( side ) or {}
	return t.nameStringTableID
end

--- Returns the Material for the brush-side.
--- @param side number
--- @return IMaterial
function meta_brush:GetMaterial( side )
	if self._material and self._material[side] then return self._material[side] end
	if not self._material then self._material = {} end

	self._material[side] = Material( self:GetTexture( side ) or "__error" )
	return self._material[side]
end

--- Returns true if the point is inside the brush
--- @param position Vector
--- @return boolean
function meta_brush:IsPointInside( position )
	for i = 1, self.numsides do
		local side = self.sides[i]
		local plane = side.plane
		if plane.normal:Dot( position ) - plane.dist > DIST_EPSILON then
			return false
		end
	end

	return true
end
