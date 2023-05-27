-- Copyright © 2022-2072, Nak, https://steamcommunity.com/id/Nak2/
-- All Rights Reserved. Not allowed to be reuploaded.

local band = bit.band
local meta = NikNaks.__metatables["BSP"]

--- @class StaticProp
--- @field Index number
--- @field version number
--- @field Origin Vector
--- @field Angles Angle
--- @field PropType string
--- @field First_leaf number
--- @field LeafCount number
--- @field Solid number
--- @field Flags? number
--- @field Skin number
--- @field FadeMinDist number
--- @field FadeMaxDist number
--- @field LightingOrigin Vector
--- @field ForcedFadeScale? number
--- @field MinDXLevel? number
--- @field MaxDXLevel? number
--- @field lightmapResolutionX? number
--- @field lightmapResolutionY? number
--- @field MinCPULevel? number
--- @field MaxCPULevel? number
--- @field MinGPULevel? number
--- @field MaxGPULevel? number
--- @field DiffuseModulation? Color
--- @field DisableX360? boolean
--- @field FlagsEx? number
--- @field UniformScale? number
local meta_staticprop = {}
meta_staticprop.__index = meta_staticprop
meta_staticprop.__tostring = function(self) return "Static Prop" .. (self.PropType  and " [" .. self.PropType .. "]" or "") end
meta_staticprop.MetaName = "StaticProp"
NikNaks.__metatables["StaticProp"] = meta_staticprop

local version = {}
	-- Base version from Wiki. Most HL2 maps are version 5.
	version[4] = function( f, obj, m )
		obj.Origin = f:ReadVector()								-- Vector (3 float) 12 bytes
		obj.Angles = f:ReadAngle()								-- Angle (3 float) 	12 bytes
		obj.PropType = m[f:ReadUShort() + 1]					-- unsigned short 			2 bytes
		obj.First_leaf = f:ReadUShort()							-- unsigned short 			2 bytes
		obj.LeafCount = f:ReadUShort()							-- unsigned short 			2 bytes
		obj.Solid = f:ReadByte()								-- unsigned char 			1 byte
		obj.Flags = f:ReadByte()								-- unsigned char 			1 byte
		obj.Skin = f:ReadLong()									-- int 						4 bytes
		obj.FadeMinDist = f:ReadFloat()							-- float 					4 bytes
		obj.FadeMaxDist = f:ReadFloat()							-- float 					4 bytes
		obj.LightingOrigin = f:ReadVector()						-- Vector (3 float) 		12 bytes
		return 448
	end

	-- Fade scale added.
	version[5] = function( f, obj, m)
		version[4]( f, obj, m )
		obj.ForcedFadeScale = f:ReadFloat()					-- float 					4 bytes
		return 480
	end

	-- Minimum and maximum DX-level
	version[6] = function( f, obj, m)
		version[5]( f, obj, m )
		obj.MinDXLevel = f:ReadUShort()					-- unsigned short 			2 bytes
		obj.MaxDXLevel = f:ReadUShort()					-- unsigned short 			2 bytes
		return 512
	end

	-- Color modulation added
	version[7] = function( f, obj, m )
		version[6]( f, obj, m )
		obj.DiffuseModulation = f:ReadColor()
		return 544
	end

	-- Removal of DX-Level. Possible for Linux and console support.
	version[8] = function( f, obj, m )
		version[5]( f,obj, m )
		obj.MinCPULevel = f:ReadByte()					-- unsigned char 			1 byte
		obj.MaxCPULevel = f:ReadByte()					-- unsigned char 			1 byte
		obj.MinGPULevel = f:ReadByte()					-- unsigned char 			1 byte
		obj.MaxGPULevel = f:ReadByte()					-- unsigned char 			1 byte
		obj.DiffuseModulation = f:ReadColor()
		return 544
	end

	-- Added Dissable-flag for X360
	version[9] = function( f, obj, m )
		version[8]( f, obj, m )
		-- The first byte seems to be the indecator.
		-- All maps have the first byte as 0x00, where the L4D2 map; 'c2m4_barns.bsp', tells us it is 0x01 is true.
		obj.DisableX360 = f:ReadByte() == 1 	-- The first byte is the indecator
		-- The last 3 bytes seems to be random data, to fill out the 32bit network-limit
		f:Skip( 24 )
		return 576
	end

	-- This version is for TF2 and some CS:S maps. 
	-- Was build on version 6. Guess they where never meant to be released on consoles and only PC ( Since they use DXLevel )
	version[10] = function( f, obj, m )
		version[6]( f, obj, m )
		obj.lightmapResolutionX = f:ReadLong()
		obj.lightmapResolutionY = f:ReadLong()
		return 576
	end

	-- ( Version 7* ) This version is for some CSGO maps. I guess it was for the console support.
	version["10A"] = function( f, obj, m )
		version[9]( f, obj, m )
		obj.FlagsEx = f:ReadULong()
		return 608
	end

	-- The newest CSGO maps. Might have left the console's behind with the newest map versions.
	version[11] = function( f, obj, m )
		local q = version[9]( f, obj, m )
		obj.FlagsEx = f:ReadULong()
		obj.UniformScale = f:ReadFloat()
		return q + 64
	end

--- @class StaticProp

--- @param f BitBuffer
--- @param ver number
--- @return StaticProp, number
local function CreateStaticProp( f, ver, m )
	local obj = {}
	local startTell = f:Tell()

	version[ver]( f, obj, m )
	obj.version = ver

	local sizeUsed = f:Tell() - startTell
	return setmetatable( obj, meta_staticprop ), sizeUsed
end

--- Returns a list of staticprops.
--- @return StaticProp[]
function meta:GetStaticProps()
	if self._staticprops then return self._staticprops end

	local gameLump = self:GetGameLump( 1936749168 ) -- 1936749168 == "sprp"
	local b = gameLump.buffer
	local propVersion = gameLump.version

	if b:Size() < 1 or not NikNaks._Source:find( "niknak" ) then -- This map doesn't have staticprops, or doesn't support them.
		self._staticprops = {}
		self._staticprops_mdl = {}
		return self._staticprops
	end

	if propVersion > 11 then
		ErrorNoHalt( self._mapfile .. " has an unknown static-prop version!" )
		self._staticprops = {}
		self._staticprops_mdl = {}
		return self._staticprops
	end

	-- Load the model list. This list is used by the static_props.
	--- @type string[]
	self._staticprops_mdl = {}

	local n = b:ReadLong()
	if n > 16384 then -- Check if we overread the max static props.
		ErrorNoHalt( self._mapfile .. " has more than 16384 models!" )
		self._staticprops = {}
		return self._staticprops
	end

	for i = 1, n do
		-- All model-paths are saved as char[128]. Any overflow are nullbytes.
		local model = ""

		for i2 = 1, 128 do
			local c = string.char( b:ReadByte() )
			if string.match( c,"[%w_%-%.%/]" ) then -- Just in case, we check for "valid" chars instead.
				model = model .. c
			end
		end

		self._staticprops_mdl[i] = model
	end

	-- Read the leaf-array. (Unused atm). Prob an index for the static props. However each static-prop already hold said data.
	b:Skip( 16 * b:ReadLong() )

	-- Read static props
	local count = b:ReadLong()
	if count > 16384 then -- Check if we are above the max staticprop.
		ErrorNoHalt( self._mapfile .. " has more than 16384 staticprops!" )
		self._staticprops = {}
		return self._staticprops
	end

	-- We calculate the amount of static props within this space. It is more stable.
	local staticStart = b:Tell()
	local endPos = b:Size()
	local staticSize = ( endPos - staticStart ) / count
	local staticUsed

	--- @type StaticProp[]
	self._staticprops = {}

	-- Check for the 7* version.
	if staticSize == 608 and propVersion == 10 then
		propVersion = "10A"
	end

	for i = 0, count - 1 do
		-- This is to try and get as much valid data we can.
		b:Seek( staticStart + staticSize * i )
		local sObj, sizeused = CreateStaticProp( b, propVersion, self._staticprops_mdl, staticSize )
		staticUsed = staticUsed or sizeused
		sObj.Index = i
		self._staticprops[i] = sObj
	end

	if staticUsed and staticUsed ~= staticSize then
		ErrorNoHalt( "Was unable to parse " .. self._mapfile .. "'s StaticProps correctly!" )
	end

	return self._staticprops
end

--- Returns the static-prop object from said index.
--- @param index number
--- @return StaticProp
function meta:GetStaticProp( index )
	return self:GetStaticProps()[index]
end

--- Returns a list of all static-prop models used by the map.
--- @return string[]
function meta:GetStaticPropModels()
	if self._staticprops_mdl then return self._staticprops_mdl end

	self:GetStaticProps() -- If no model list, then load the gamelump.
	return self._staticprops_mdl
end

--- Returns a list of all static-props matching the model.
--- @param model string
--- @return StaticProp[]
function meta:FindStaticByModel( model )
	local t = {}

	for _, v in pairs( self:GetStaticProps() ) do
		if v.PropType == model then
			t[#t + 1] = v
		end
	end

	return t
end

--- Returns a list of all static-props, within the specified box.
--- @param boxMins Vector
--- @param boxMaxs Vector
--- @return StaticProp[]
function meta:FindStaticInBox( boxMins, boxMaxs )
	local t = {}

	for _, v in pairs( self:GetStaticProps() ) do
		local origin = v.Origin
		if origin and v.Origin:WithinAABox( boxMins, boxMaxs ) then
			t[#t + 1] = v
		end
	end

	return t
end

--- Returns a list of all static-props, within the specified sphere.
--- @param origin Vector
--- @param radius number
--- @return StaticProp[]
function meta:FindStaticInSphere( origin, radius )
	radius = radius ^ 2
	local t = {}

	for _, v in pairs( self:GetStaticProps() ) do
		local spOrigin = v.Origin
		if spOrigin and spOrigin:DistToSqr( origin ) <= radius then
			t[#t + 1] = v
		end
	end

	return t
end

--- Returns the StaticProp index
function meta_staticprop:GetIndex()
	return self.Index
end

--- Returns the origin
function meta_staticprop:GetPos()
	return self.Origin
end

--- Returns the angles
function meta_staticprop:GetAngles()
	return self.Angles
end

--- Returns the model path
function meta_staticprop:GetModel()
	return self.PropType
end

--- Returns the skin index
function meta_staticprop:GetSkin()
	return self.Skin or 0
end

--- @return Color
function meta_staticprop:GetColor()
	return self.DiffuseModulation or color_white
end

function meta_staticprop:GetScale()
	return self.UniformScale or 1
end
meta_staticprop.GetModelScale = meta_staticprop.GetScale

--- Returns the solid enum. See: https://wiki.facepunch.com/gmod/Enums/SOLID
function meta_staticprop:GetSolid()
	return self.Solid
end

--- Returns the lighting origin
function meta_staticprop:GetLightingOrigin()
	return self.LightingOrigin
end

--- Returns the flags
function meta_staticprop:GetFlags()
	return self.Flags
end

--- Returns true if the staticprop has a flag.
--- @param flag number
--- @return boolean
function meta_staticprop:HasFlag( flag )
	return band( self:GetFlags(), flag ) ~= 0
end

--- Returns true if the static prop is disabled on X360.
--- @return boolean
function meta_staticprop:GetDisableX360()
	return self.DisableX360 or false
end

--- Returns the model bounds.
--- @return Vector
--- @return Vector
function meta_staticprop:GetModelBounds()
	local a, b = NikNaks.ModelSize( self:GetModel() )
	local s = self:GetScale()
	return a * s, b * s
end
meta_staticprop.GetModelRenderBounds = meta_staticprop.GetModelBounds
meta_staticprop.GetRenderBounds = meta_staticprop.GetModelBounds

-- Fade Functions

function meta_staticprop:GetFadeMinDist()
	return self.FadeMinDist
end

function meta_staticprop:GetFadeMaxDist()
	return self.FadeMaxDist
end

function meta_staticprop:GetForceFadeScale()
	return self.ForcedFadeScale or 1
end

-- "Other"

--[[ DXLevel
	0 = Ignore
	70 = DirectX 7
	80 = DirectX 8
	81 = DirectX 8.1
	90 = DirectX 9
	95 = DirectX 9+ ( 9.3 )
	98 = DirectX 9Ex
]]
function meta_staticprop:GetDXLevel()
	return self.MinDXLevel or 0, self.MaxDXLevel or 0
end

if CLIENT then
	-- Checks to see if the client has the directX level required to render the static prop.
	function meta_staticprop:HasDXLevel()
		local num = render.GetDXLevel()
		if self.MinDXLevel ~= 0 and num < self.MinDXLevel then return false end
		if self.MaxDXLevel ~= 0 and num > self.MaxDXLevel then return false end
		return true
	end
end

--[[	There must be a list of CPU's and what level they are.
	CPU Level
	0 = Ignore
	1 = "Low"
	2 = "Medium"
	3 = "High"
]]
function meta_staticprop:GetCPULevel()
	return self.MinCPULevel or 0, self.MaxCPULevel or 0
end

--[[	There must be a list of GPU's and what level they are.
	GPU Level
	0 = Ignore
	1 = "Low"
	2 = "Medium"
	3 = "High"
]]
function meta_staticprop:GetGPULevel()
	return self.MinGPULevel or 0, self.MaxGPULevel or 0
end

-- Allows to set the lightmap resolution for said static-prop.
-- Checkout https://tf2maps.net/threads/guide-lightmap-optimization.33113/ for more info
function meta_staticprop:GetLightMapResolution()
	return self.lightmapResolutionX, self.lightmapResolutionY
end

--- Returns the "Further" BitFlags. Seems to be only used for the "STATIC_PROP_FLAGS_EX_DISABLE_CSM" flag.
--- @return number
function meta_staticprop:GetFlagExs()
	return self.FlagsEx or 0
end

--- Returns true if the staticprop has an exflag.
--- @param flag number
--- @return boolean
function meta_staticprop:HasFlagEx( flag )
	return band( self:GetFlagExs(), flag ) ~= 0
end

--- Returns the version of the static props.
--- Note: version 7* will be returned as a string: "10A"
function meta_staticprop:GetVersion()
	return self.version
end
