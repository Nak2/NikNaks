-- Copyright © 2022-2072, Nak, https://steamcommunity.com/id/Nak2/
-- All Rights Reserved. Not allowed to be reuploaded.
-- License: https://github.com/Nak2/NikNaks/blob/main/LICENSE

--[[
	Detail props: the grass, plants and small models that vbsp scatters over surfaces (see detail.vbsp).
	They live in the game lump 'dprp':

		int  modelCount;   char modelName[128] x modelCount                      					-- the detail models
		int  spriteCount;  float ulX, ulY, lrX, lrY, texULx, texULy, texLRx, texLRy  x spriteCount  -- rectangles in the sprite sheet
		int  objectCount;  DetailObjectLump_t x objectCount                      					-- 52 bytes each, below

	Each object is
		Vector origin; QAngle angles; ushort index; ushort leaf; ColorRGBExp32 lighting; uint lightStyles;
		byte lightStyleCount, swayAmount, shapeAngle, shapeSize, orientation; byte pad[3]; byte type; byte pad[3]; float scale

	`index` is an index into the model list for models, and into the sprite list for sprites.
	The sprite sheet is the material in the world entity's "detailmaterial" key, see BSPObject:GetDetailMaterial().
]]

--- @class BSPObject
local meta = NikNaks.__metatables["BSP"]

local GAMELUMP_DETAIL_PROPS = 0x64707270 -- 'dprp'
local NAME_BITS, SPRITE_BITS, OBJECT_BITS = 128 * 8, 8 * 32, 52 * 8

--- @enum NikNaks.DETAIL_PROP_TYPE
NikNaks.DETAIL_PROP_TYPE = {
	MODEL = 0,       -- A model, see BSPDetailInfo.models
	SPRITE = 1,      -- A sprite from the sprite sheet. Usually turns to face the player.
	SHAPE_CROSS = 2, -- Sprites in a cross
	SHAPE_TRI = 3,   -- Sprites in a triangle
}

--- @enum NikNaks.DETAIL_PROP_ORIENT
NikNaks.DETAIL_PROP_ORIENT = {
	NORMAL = 0,
	SCREEN_ALIGNED = 1,
	SCREEN_ALIGNED_VERTICAL = 2,
}

--- @class BSPDetailSprite # A rectangle in the sprite sheet, and how big the sprite is
--- @field ul number[] # { x, y }: upper left corner of the sprite, relative to its origin, before scale
--- @field lr number[] # { x, y }: lower right corner of the sprite, relative to its origin, before scale
--- @field texUL number[] # { u, v }: upper left in the sprite sheet (0 - 1)
--- @field texLR number[] # { u, v }: lower right in the sprite sheet (0 - 1)

--- @class BSPDetailInfo
--- @field version number
--- @field models table<number, string> # Model paths (0-based, as the objects index them)
--- @field sprites table<number, BSPDetailSprite> # Sprites in the sprite sheet (0-based)
--- @field count number # How many detail objects the map has
--- @field bit number # Where the objects start in the game lump, in bits

--- @class BSPDetailProp
--- @field Origin Vector
--- @field Angles Angle
--- @field Index number # Into BSPDetailInfo.models or .sprites, depending on Type
--- @field Leaf number
--- @field Lighting { r: number, g: number, b: number, exponent: number } # RGBExp32: the light at the object
--- @field LightStyles number
--- @field LightStyleCount number
--- @field SwayAmount number
--- @field ShapeAngle number
--- @field ShapeSize number
--- @field Orientation number # NikNaks.DETAIL_PROP_ORIENT
--- @field Type number # NikNaks.DETAIL_PROP_TYPE
--- @field Scale number # For sprites

---Reads the header of the detail props: the model and sprite lists, and how many objects there are.
---Does not read the objects, see BSPObject:GetDetailProp(). Returns nil if the map has no (readable) detail props.
--- @return BSPDetailInfo?
function meta:GetDetailPropInfo()
	if self._detailInfo ~= nil then return self._detailInfo or nil end
	self._detailInfo = false

	local lump = self:GetGameLump( GAMELUMP_DETAIL_PROPS )
	if not lump or lump.version < 0 then return nil end

	local b = lump.buffer
	local size = b:Size()
	if size < 3 * 32 then return nil end
	b:Seek( 0 )

	--- @type BSPDetailInfo
	local info = { version = lump.version, models = {}, sprites = {}, count = 0, bit = 0 }

	-- Counts are checked against the size of the lump before anything is read with them
	local modelCount = b:ReadLong()
	if modelCount < 0 or 32 + modelCount * NAME_BITS + 32 > size then return nil end
	for i = 0, modelCount - 1 do
		info.models[i] = ( string.gsub( b:Read( 128 ), "%z.*$", "" ) )
	end

	local spriteCount = b:ReadLong()
	if spriteCount < 0 or b:Tell() + spriteCount * SPRITE_BITS + 32 > size then return nil end
	for i = 0, spriteCount - 1 do
		local ulx, uly, lrx, lry = b:ReadFloat(), b:ReadFloat(), b:ReadFloat(), b:ReadFloat()
		local tux, tuy, tlx, tly = b:ReadFloat(), b:ReadFloat(), b:ReadFloat(), b:ReadFloat()
		info.sprites[i] = { ul = { ulx, uly }, lr = { lrx, lry }, texUL = { tux, tuy }, texLR = { tlx, tly } }
	end

	local count = b:ReadLong()
	if count < 0 or b:Tell() + count * OBJECT_BITS > size then return nil end

	info.count = count
	info.bit = b:Tell()
	self._detailInfo = info
	return info
end

---Reads one detail object. Index is 0-based, up to BSPDetailInfo.count - 1.
--- @param index number
--- @return BSPDetailProp?
function meta:GetDetailProp( index )
	local info = self:GetDetailPropInfo()
	if not info or index < 0 or index >= info.count then return nil end

	local b = self:GetGameLump( GAMELUMP_DETAIL_PROPS ).buffer
	b:Seek( info.bit + index * OBJECT_BITS )

	local origin = b:ReadVector()
	local angles = b:ReadAngle()
	local modelIndex = b:ReadUShort()
	local leaf = b:ReadUShort()
	local lr, lg, lb, le = b:ReadByte(), b:ReadByte(), b:ReadByte(), b:ReadSignedByte()
	local lightStyles = b:ReadULong()
	local lightStyleCount, sway, shapeAngle, shapeSize, orientation = b:ReadByte(), b:ReadByte(), b:ReadByte(), b:ReadByte(), b:ReadByte()
	b:Skip( 24 )
	local propType = b:ReadByte()
	b:Skip( 24 )
	local scale = b:ReadFloat()

	return {
		Origin = origin, Angles = angles, Index = modelIndex, Leaf = leaf,
		Lighting = { r = lr, g = lg, b = lb, exponent = le }, LightStyles = lightStyles, LightStyleCount = lightStyleCount,
		SwayAmount = sway, ShapeAngle = shapeAngle, ShapeSize = shapeSize, Orientation = orientation,
		Type = propType, Scale = scale,
	}
end

---Reads all the detail objects. A map can have a lot of them (100 000+), so for big maps read them
---one at a time with BSPObject:GetDetailProp(), or use only some of them.
--- @return BSPDetailProp[] # 0-based
function meta:GetDetailProps()
	local info = self:GetDetailPropInfo()
	local out = {}
	if not info then return out end

	for i = 0, info.count - 1 do
		out[i] = self:GetDetailProp( i )
	end
	return out
end
