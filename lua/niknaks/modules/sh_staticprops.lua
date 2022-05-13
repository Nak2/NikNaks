-- Copyright © 2022-2072, Nak, https://steamcommunity.com/id/Nak2/
-- All Rights Reserved. Not allowed to be reuploaded.

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
---@return any
function meta:GetScale()
	return self.UniformScale
end
meta.GetModelScale = meta.GetScale

---Returns the solid enum. See: https://wiki.facepunch.com/gmod/Enums/SOLID
---@return number
function meta:GetSolid()
	return self.Solid
end

---Returns the lighting origion.
---@return any
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
	return bit.band(self:GetFlags(), flag) == flag
end

---Returns true if the static prop is disabled on X360.
---Note: Is slightly unstable.
---@return boolean
function meta:GetDisableX360()
	return self.DisableX360 or false
end

---Returns the model bounds.
---@return Vector
---@return Vector
function meta:GetModelBounds()
	local a, b = ModelSize( self:GetModel() )
	return a * self:GetScale(), b * self:GetScale()
end
meta.GetModelRenderBounds = meta.GetModelBounds
meta.GetRenderBounds = meta.GetModelBounds