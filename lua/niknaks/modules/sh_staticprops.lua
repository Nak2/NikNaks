-- Copyright © 2022-2072, Nak, https://steamcommunity.com/id/Nak2/
-- All Rights Reserved. Not allowed to be reuploaded.
local band = bit.band
---@class StaticProps
local meta = {}
meta.__index = meta
meta.__tostring = function(self) return "Static Prop" .. (self.PropType  and " [" .. self.PropType .. "]" or "") end
meta.MetaName = "StaticProp"
debug.getregistry().StaticProp = meta

---Returns the index.
---@return number
function meta:GetIndex()
	return self.Index
end

---Returns the position
---@return Vector
function meta:GetPos()
	return self.Origin
end

---Returns the angle
---@return Angle
function meta:GetAngles()
	return self.Angles
end

---Returns the model
---@return string
function meta:GetModel()
	return self.PropType
end

---Returns the skin
---@return number
function meta:GetSkin()
	return self.Skin or 0
end

---Returns the color.
---@return Color
function meta:GetColor()
	return self.DiffuseModulation or color_white
end

---Returns the model scale.
---@return number
function meta:GetScale()
	return self.UniformScale or 1
end
meta.GetModelScale = meta.GetScale

---Returns the solid enum. See: https://wiki.facepunch.com/gmod/Enums/SOLID
---@return number
function meta:GetSolid()
	return self.Solid
end

---Returns the lighting origion.
---@return Vector
function meta:GetLightingOrigin()
	return self.LightingOrigin
end

---Returns the flags.
---@return number
function meta:GetFlags()
	return self.Flags
end

---Returns true if the staticprop has a flag.
---@param flag number
---@return boolean
function meta:HasFlag( flag )
	return band(self:GetFlags(), flag) ~= 0
end

---Returns true if the static prop is disabled on X360.
---@return boolean
function meta:GetDisableX360()
	return self.DisableX360 or false
end

---Returns the model bounds.
---@return Vector
---@return Vector
function meta:GetModelBounds()
	local a, b = NikNaks.ModelSize( self:GetModel() )
	local s = self:GetScale()
	return a * s, b * s
end
meta.GetModelRenderBounds = meta.GetModelBounds
meta.GetRenderBounds = meta.GetModelBounds

-- Fade Functions
function meta:GetFadeMinDist()
	return self.FadeMinDist
end

function meta:GetFadeMaxDist()
	return self.FadeMaxDist
end

function meta:GetForceFadeScale()
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
function meta:GetDXLevel()
	return self.MinDXLevel or 0, self.MaxDXLevel or 0
end

if CLIENT then
	-- Checks to see if the client has the directX level required to render the static prop.
	function meta:HasDXLevel()
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
function meta:GetCPULevel()
	return self.MinCPULevel or 0, self.MaxCPULevel or 0
end

--[[	There must be a list of GPU's and what level they are.
	GPU Level
	0 = Ignore
	1 = "Low"
	2 = "Medium"
	3 = "High"
]]
function meta:GetGPULevel()
	return self.MinGPULevel or 0, self.MaxGPULevel or 0
end

-- Allows to set the lightmap resolution for said static-prop.
-- Checkout https://tf2maps.net/threads/guide-lightmap-optimization.33113/ for more info
function meta:GetLightMapResolution()
	return self.lightmapResolutionX, self.lightmapResolutionY
end

---Returns the "Further" BitFlags. Seems to be used for the "STATIC_PROP_FLAGS_EX_DISABLE_CSM" flag.
---@return number
function meta:GetFlagExs()
	return self.FlagsEx or 0
end

---Returns true if the staticprop has an exflag.
---@param flag number
---@return boolean
function meta:HasFlagEx( flag )
	return band(self:GetFlags(), FlagsEx) ~= 0
end

-- Returns the version of the static props.
-- Note: version 7* will be returned as a string: "10A"
function meta:GetVersion()
	return self.version
end