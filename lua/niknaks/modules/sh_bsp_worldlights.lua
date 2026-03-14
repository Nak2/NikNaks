-- Copyright © 2022-2072, Nak, https://steamcommunity.com/id/Nak2/
-- All Rights Reserved. Not allowed to be reuploaded.
-- License: https://github.com/Nak2/NikNaks/blob/main/LICENSE

local obj_tostring = "BSP %s [ %s ]"
local format = string.format

--- @class BSPObject
local meta = NikNaks.__metatables["BSP"]

--[[
	World lights are stored in lumps 15 (LDR) and 54 (HDR).
	Each entry is a dworldlight_t struct (88 bytes = 704 bits):

	Vector  origin          12 bytes
	Vector  intensity       12 bytes  (RGB; pre-scaled by 255 * 2^exponent)
	Vector  normal          12 bytes  (spotlight / sky direction)
	int     cluster          4 bytes
	int     type             4 bytes  (emittype_t)
	int     style            4 bytes  (light style index, 0 = always on)
	float   stopdot          4 bytes  (cos of inner cone angle; spotlights)
	float   stopdot2         4 bytes  (cos of outer cone angle; spotlights)
	float   exponent         4 bytes  (falloff exponent)
	float   radius           4 bytes  (0 = no distance limit)
	float   constant_attn    4 bytes
	float   linear_attn      4 bytes
	float   quadratic_attn   4 bytes
	int     flags            4 bytes
	int     texinfo          4 bytes
	int     owner            4 bytes  (entity index that owns this light)

	emittype_t values:
	  0 = emit_surface    (area / 90-degree spotlight on a surface)
	  1 = emit_point      (omnidirectional point light)
	  2 = emit_spotlight  (cone spotlight)
	  3 = emit_skylight   (sun / directional env_light)
	  4 = emit_quakelight (HL1-style linear falloff point)
	  5 = emit_skyambient (ambient sky fill)
]]

local WORLDLIGHT_SIZE_BITS = 704  -- 88 bytes

--- @class BSPWorldLight
--- @field origin Vector        # World-space origin of the light source
--- @field intensity Vector     # Pre-scaled RGB intensity
--- @field normal Vector        # Direction the light faces (spotlights / sky)
--- @field cluster number       # Visibility cluster the light is in
--- @field type number          # Emit type (0-5; see EMIT_* constants)
--- @field style number         # Light style index (0 = always on)
--- @field stopdot number       # cos( inner cone angle ) for spotlights
--- @field stopdot2 number      # cos( outer cone angle ) for spotlights
--- @field exponent number      # Distance falloff exponent
--- @field radius number        # Max light radius (0 = unlimited)
--- @field constant_attn number # Constant attenuation term
--- @field linear_attn number   # Linear attenuation term
--- @field quadratic_attn number# Quadratic attenuation term
--- @field flags number         # Misc flags
--- @field texinfo number       # Texture info index (-1 if none)
--- @field owner number         # Source entity index (-1 if world)
--- @field __map BSPObject

local meta_light = {}
meta_light.__index = meta_light
meta_light.__tostring = function( self )
	return format( obj_tostring, "WorldLight", self.__id )
end
meta_light.MetaName = "BSP WorldLight"
NikNaks.__metatables["BSP WorldLight"] = meta_light

-- Emit type constants --------------------------------------------------------
NikNaks.EMIT_SURFACE    = 0
NikNaks.EMIT_POINT      = 1
NikNaks.EMIT_SPOTLIGHT  = 2
NikNaks.EMIT_SKYLIGHT   = 3
NikNaks.EMIT_QUAKELIGHT = 4
NikNaks.EMIT_SKYAMBIENT = 5

-- Parsing helper -------------------------------------------------------------
--- @param self BSPObject
--- @param lumpIdx number
--- @param cacheKey string
--- @return BSPWorldLight[]
local function parseWorldLights( self, lumpIdx, cacheKey )
	if self[cacheKey] then return self[cacheKey] end

	local data  = self:GetLump( lumpIdx )
	local count = math.floor( data:Size() / WORLDLIGHT_SIZE_BITS )

	--- @type BSPWorldLight[]
	local t = {}

	for i = 0, count - 1 do
		--- @class BSPWorldLight
		local wl = setmetatable( {}, meta_light )
		wl.__map         = self
		wl.__id          = i
		wl.origin        = data:ReadVector()
		wl.intensity     = data:ReadVector()
		wl.normal        = data:ReadVector()
		wl.cluster       = data:ReadLong()
		wl.type          = data:ReadLong()
		wl.style         = data:ReadLong()
		wl.stopdot       = data:ReadFloat()
		wl.stopdot2      = data:ReadFloat()
		wl.exponent      = data:ReadFloat()
		wl.radius        = data:ReadFloat()
		wl.constant_attn = data:ReadFloat()
		wl.linear_attn   = data:ReadFloat()
		wl.quadratic_attn= data:ReadFloat()
		wl.flags         = data:ReadLong()
		wl.texinfo       = data:ReadLong()
		wl.owner         = data:ReadLong()
		t[i]             = wl
	end

	self[cacheKey] = t
	self:ClearLump( lumpIdx )
	return t
end

-- BSPObject methods ----------------------------------------------------------

--- Returns all LDR world lights (lump 15).
--- @return BSPWorldLight[]
function meta:GetWorldLights()
	return parseWorldLights( self, 15, "_worldlights" )
end

--- Returns all HDR world lights (lump 54).
--- @return BSPWorldLight[]
function meta:GetWorldLightsHDR()
	return parseWorldLights( self, 54, "_worldlightsHDR" )
end

--- Returns the world light at the given index (LDR).
--- @param index number
--- @return BSPWorldLight?
function meta:GetWorldLight( index )
	return self:GetWorldLights()[index]
end

--- Returns the nearest world light to the given position.
--- @param position Vector
--- @param hdr boolean? # If true, uses HDR lights (lump 54). Default is LDR (lump 15).
--- @return BSPWorldLight?
function meta:FindNearestLight( position, hdr )
	local lights = hdr and self:GetWorldLightsHDR() or self:GetWorldLights()
	local bestLight, bestDistSqr

	for _, wl in pairs( lights ) do
		local d = wl.origin:DistToSqr( position )
		if not bestDistSqr or d < bestDistSqr then
			bestDistSqr = d
			bestLight   = wl
		end
	end

	return bestLight
end

--- Returns all world lights of a given emit type.
--- @param emitType number # One of NikNaks.EMIT_* constants
--- @param hdr boolean?   # If true, uses HDR data. Default is LDR.
--- @return BSPWorldLight[]
function meta:FindLightsByType( emitType, hdr )
	local lights = hdr and self:GetWorldLightsHDR() or self:GetWorldLights()
	local t, n  = {}, 1
	for _, wl in pairs( lights ) do
		if wl.type == emitType then
			t[n] = wl
			n    = n + 1
		end
	end
	return t
end

--- Returns all world lights within the given radius of a position.
--- @param position Vector
--- @param radius number
--- @param hdr boolean? # If true, uses HDR data. Default is LDR.
--- @return BSPWorldLight[]
function meta:FindLightsInRadius( position, radius, hdr )
	local lights   = hdr and self:GetWorldLightsHDR() or self:GetWorldLights()
	local radiusSqr = radius * radius
	local t, n     = {}, 1
	for _, wl in pairs( lights ) do
		if wl.origin:DistToSqr( position ) <= radiusSqr then
			t[n] = wl
			n    = n + 1
		end
	end
	return t
end

-- BSPWorldLight methods -------------------------------------------------------

--- Returns the index of this light.
--- @return number
function meta_light:GetIndex()
	return self.__id
end

--- Returns the world-space origin of the light.
--- @return Vector
function meta_light:GetPos()
	return self.origin
end

--- Returns the pre-scaled RGB intensity as a Vector (r, g, b ∈ [0, ∞)).
--- @return Vector
function meta_light:GetIntensity()
	return self.intensity
end

--- Returns the RGB intensity as a Color (values clamped to 0-255).
--- @return Color
function meta_light:GetColor()
	return Color(
		math.Clamp( self.intensity.x, 0, 255 ),
		math.Clamp( self.intensity.y, 0, 255 ),
		math.Clamp( self.intensity.z, 0, 255 )
	)
end

--- Returns the facing direction of the light (relevant for spotlights and sky lights).
--- @return Vector
function meta_light:GetNormal()
	return self.normal
end

--- Returns the emit type of this light (one of NikNaks.EMIT_* constants).
--- @return number
function meta_light:GetType()
	return self.type
end

--- Returns the light style index (0 = always on).
--- @return number
function meta_light:GetStyle()
	return self.style
end

--- Returns the maximum radius of this light (0 = unlimited).
--- @return number
function meta_light:GetRadius()
	return self.radius
end

--- Returns true if this is a point light.
--- @return boolean
function meta_light:IsPoint()
	return self.type == NikNaks.EMIT_POINT
end

--- Returns true if this is a spotlight.
--- @return boolean
function meta_light:IsSpotlight()
	return self.type == NikNaks.EMIT_SPOTLIGHT
end

--- Returns true if this is a directional sky (sun) light.
--- @return boolean
function meta_light:IsSkyLight()
	return self.type == NikNaks.EMIT_SKYLIGHT
end

--- Returns true if this is an ambient sky fill light.
--- @return boolean
function meta_light:IsSkyAmbient()
	return self.type == NikNaks.EMIT_SKYAMBIENT
end

--- Returns the inner and outer cone angles (in degrees) for spotlights.
--- Both return 0 for non-spotlight types.
--- @return number innerDeg # Inner (full-bright) cone angle
--- @return number outerDeg # Outer (falloff-to-zero) cone angle
function meta_light:GetConeAngles()
	return math.deg( math.acos( math.Clamp( self.stopdot,  -1, 1 ) ) ),
	       math.deg( math.acos( math.Clamp( self.stopdot2, -1, 1 ) ) )
end

--- Returns the attenuation coefficients: constant, linear, quadratic.
--- @return number constant
--- @return number linear
--- @return number quadratic
function meta_light:GetAttenuation()
	return self.constant_attn, self.linear_attn, self.quadratic_attn
end

--- Calculates the approximate scalar brightness at a given world position.
--- Uses the standard quadratic attenuation formula:
---   brightness = 1 / (constant + linear*d + quadratic*d*d)
--- where d is the distance to the light. Returns 0 for sky/ambient types.
--- @param position Vector
--- @return number # Brightness in [0, 1] (clamped)
function meta_light:BrightnessAt( position )
	if self.type == NikNaks.EMIT_SKYLIGHT or self.type == NikNaks.EMIT_SKYAMBIENT then
		return 0
	end

	local d = self.origin:Distance( position )
	if self.radius > 0 and d > self.radius then return 0 end

	local c, l, q = self.constant_attn, self.linear_attn, self.quadratic_attn
	local denom = c + l * d + q * d * d
	if denom <= 0 then return 1 end
	return math.Clamp( 1 / denom, 0, 1 )
end

--- Returns the visibility cluster this light belongs to.
--- @return number
function meta_light:GetCluster()
	return self.cluster
end

--- Returns the entity index that created this light (-1 for world geometry lights).
--- @return number
function meta_light:GetOwner()
	return self.owner
end
