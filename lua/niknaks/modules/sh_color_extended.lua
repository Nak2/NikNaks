-- Copyright © 2022-2072, Nak, https://steamcommunity.com/id/Nak2/
-- All Rights Reserved. Not allowed to be reuploaded.
local NikNaks = NikNaks
local COLOR = FindMetaTable("Color")

local clamp = math.Clamp
local Color, round = Color, math.Round
local min, max, abs = math.min, math.max, math.abs
local string_format, string_sub = string.format, string.sub

-- Color enums
	NikNaks.SERVER_COLOR= Color(156, 241, 255, 200)
	NikNaks.CLIENT_COLOR= Color(255, 241, 122, 200)
	NikNaks.MENU_COLOR 	= Color(100, 220, 100, 200)
	NikNaks.REALM_COLOR = SERVER and NikNaks.SERVER_COLOR or CLIENT and NikNaks.CLIENT_COLOR or MENU_DLL and NikNaks.MENU_COLOR
	NikNaks.color_error_server	= Color(136, 221, 255)
	NikNaks.color_error_client	= Color(255, 221, 102)
	NikNaks.color_error_menu 	= Color(120, 220, 100)
	
	---Returns the luminance amount. How "bright" a color is between 0 and 255.
	---@param color Color
	---@return number
	function NikNaks.ColorToLuminance(color)
		return 0.2126 * color.r + 0.7152 * color.g + 0.0722 * color.b
	end

	---Returns the luminance amount. How "bright" a color is between 0 and 255.
	---@return number
	function COLOR:ToLuminance()
		return 0.2126 * self.r + 0.7152 * self.g + 0.0722 * self.b
	end

-- Hex

	---Converts a color into a hex-string.
	---@param color Color
	---@return string
	function NikNaks.ColorToHex(color)
		return "#" .. string_format("%X", color.r) .. string_format("%X", color.g) .. string_format("%X", color.b)
	end

	---Converts a color into a hex-string.
	---@return string
	function COLOR:ToHex()
		return ColorToHex(self)
	end

	---Converts a hex-stirng into a color.
	---@param str string
	---@return Color
	function NikNaks.HexToColor(str)
		str = string.gsub(str,"#","")
		local r = round( tonumber( string_sub(str,1,2), 16) )
		local g = round( tonumber( string_sub(str,3,4), 16) )
		local b = round( tonumber( string_sub(str,5,6), 16) )
		return Color(r, g, b)
	end

-- CMYK

	---Converts a color into CMYK variables.
	---@return number c
	---@return number m
	---@return number y
	---@return number j
	function COLOR:ToCMYK()
		local r, g, b = self.r / 255, self.g / 255, self.b / 255
		local k = 1 - max(r, g, b)
		local c = (1 - r - k) 	/ ( 1 - k )
		local m = (1-g-k) 		/ ( 1 - k )
		local y = (1-b-k) 		/ ( 1 - k )
		return c, m, y, k
	end

	---Converts a color into CMYK variables.
	---@return number c
	---@return number m
	---@return number y
	---@return number j
	function NikNaks.ColorToCMYK( color )
		return color:ToCMYK()
	end

	---Converts CMYK variables into a color.
	---@param c any
	---@param m any
	---@param y any
	---@param k any
	---@return Color
	function NikNaks.CMYKToColor( c, m, y, k )
		local r = math.Round( 255 * ( 1 - c ) * ( 1 - k ) )
		local g = math.Round( 255 * ( 1 - m ) * ( 1 - k ) )
		local b = math.Round( 255 * ( 1 - y ) * ( 1 - k ) )
		return Color( r, g, b )
	end

-- Color manipulation

	---Brightens the color by [0-255]-amount.
	---@param amount number
	---@return Color
	function COLOR:Brighten(amount)
		local h,s,l = ColorToHSL(self)
		return HSLToColor(h,s,l + amount)
	end

	---Darkens the color by [0-255]-amount.
	---@param amount number
	---@return Color
	function COLOR:Darken(amount)
		return self.lighten(-amount)
	end

	---Inverts the color.
	---@return Color
	function COLOR:Invert()
		return Color(255 - self.r,255 - self.g,255 - self.b)
	end

	---Turns the color into a gray-scale.
	---@return Color
	function COLOR:ToGrayscale()
		local H,S,L = self:ToHSL()
		return HSLToColor(H,0,L)
	end

	---Cartoonify the color.
	---@param color Color
	---@return Color
	function COLOR:ToCartoon(color)
		local R,G,B = color.r / 255,color.g / 255,color.b / 255
		local max_gb = max(G,B)
		local max_rb = max(R,B)
		local max_rg = max(R,G)

		local red_matter = 1 - max(R - max_gb,0)
		local green_matter = 1 - max(G - max_rb,0)
		local blue_matter = 1 - max(B - max_rg,0)

		return Color(R * green_matter * blue_matter * 255,G * red_matter * blue_matter * 255,B * red_matter * green_matter * 255)
	end

-- Color functions

	---Returns true if the color is bright. Useful to check if the text infront should be dark.
	---@return boolean
	function COLOR:IsBright()
		return ColorToLuminance(self) >= 127.5
	end

	---Returns true if the color is bright. Useful to check if the text infront should be bright.
	---@return boolean
	function COLOR:IsDark()
		return ColorToLuminance(self) < 127.5
	end

-- ColorRGBExp32
	local gamma = 2.2
	local overbrightFactor = 0.5

	-- convert texture to linear 0..1 value
	local function TexLightToLinear( col, exponent )
		return col * ( ( 2 ^ exponent ) / 255  )
	end

	-- linear (0..4) to screen corrected vertex space (0..1?)
	local function LinearToVertexLight( col )
		return overbrightFactor * ( col ^ ( 1 / gamma ) )
	end

	-- https://github.com/ValveSoftware/source-sdk-2013/blob/master/sp/src/utils/vrad/lightmap.cpp#L3551
	function NikNaks.ColorRGBExp32ToColor( struct )
		local exponent = struct.exponent
		local linearColor = {
			TexLightToLinear( struct.r, exponent ),
			TexLightToLinear( struct.g, exponent ),
			TexLightToLinear( struct.b, exponent )
		}

		local vertexColor = {
			math.min( LinearToVertexLight( linearColor[1] ), 1 ),
			math.min( LinearToVertexLight( linearColor[2] ), 1 ),
			math.min( LinearToVertexLight( linearColor[3] ), 1 )
		}

		return Color(
			math.Round( vertexColor[1] * 255 ),
			math.Round( vertexColor[2] * 255 ),
			math.Round( vertexColor[3] * 255 ),
			255
		)
	end

