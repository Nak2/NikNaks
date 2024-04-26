-- Copyright © 2022-2072, Nak, https://steamcommunity.com/id/Nak2/
-- All Rights Reserved. Not allowed to be reuploaded.

---@class Color
local COLOR = FindMetaTable("Color")

local Color, round = Color, math.Round
local max = math.max
local string_format, string_sub = string.format, string.sub

-- Color enums
	NikNaks.SERVER_COLOR= Color(156, 241, 255, 200) -- The color of the server-messages.
	NikNaks.CLIENT_COLOR= Color(255, 241, 122, 200) -- The color of the client-messages.
	NikNaks.MENU_COLOR 	= Color(100, 220, 100, 200) -- The color of the menu-messages.
	NikNaks.REALM_COLOR = SERVER and NikNaks.SERVER_COLOR or CLIENT and NikNaks.CLIENT_COLOR or MENU_DLL and NikNaks.MENU_COLOR
	NikNaks.color_error_server	= Color(136, 221, 255) -- The color of the server-errors.
	NikNaks.color_error_client	= Color(255, 221, 102) -- The color of the client-errors.
	NikNaks.color_error_menu 	= Color(120, 220, 100) -- The color of the menu-errors.

	---Returns the luminance amount. How "bright" a color is between 0 and 255.
	---@param color Color
	---@return number
	function NikNaks.ColorToLuminance(color)
		return math.Round(0.2126 * color.r + 0.7152 * color.g + 0.0722 * color.b)
	end
	local ColorToLuminance = NikNaks.ColorToLuminance

	---Returns the luminance amount. How "bright" a color is between 0 and 255.
	---@return number
	COLOR.ToLuminance = ColorToLuminance

-- Hex
	---Converts a color into a hex-string.
	---@param color Color
	---@return string
	function NikNaks.ColorToHex(color)
		return "#" .. string_format("%02X%02X%02X", color.r, color.g, color.b)
	end
	local ColorToHex = NikNaks.ColorToHex

	---Converts a color into a hex-string.
	---@return string
	COLOR.ToHex = ColorToHex

	---Converts a hex-stirng into a color.
	---@param str string
	---@return Color
	function NikNaks.HexToColor(str)
		str = string.gsub(str,"#","")
		local r = tonumber( string_sub(str,1,2), 16)
		local g = tonumber( string_sub(str,3,4), 16)
		local b = tonumber( string_sub(str,5,6), 16)
		if(r == nil or g == nil or b == nil) then return Color(255,255,255) end
		return Color(round(r), round(g), round(b))
	end

-- CMYK

	---Converts a color into CMYK variables.
	---@return number c
	---@return number m
	---@return number y
	---@return number j
	function NikNaks.ColorToCMYK( color )
		local r, g, b = color.r / 255, color.g / 255, color.b / 255
		local k = 1 - max(r, g, b)
		local n = 1 - k
		if n == 0 then return 0, 0, 0, 1 end
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
	COLOR.ToCMYK = NikNaks.ColorToCMYK

	---Converts CMYK variables into a color.
	---@param c any
	---@param m any
	---@param y any
	---@param k any
	---@return Color
	function NikNaks.CMYKToColor( c, m, y, k )
		local r = round( 255 * ( 1 - c ) * ( 1 - k ) )
		local g = round( 255 * ( 1 - m ) * ( 1 - k ) )
		local b = round( 255 * ( 1 - y ) * ( 1 - k ) )
		return Color( r, g, b )
	end

-- Color manipulation

	---Brightens the color by [0-255]-amount.
	---@param amount number
	---@return Color
	function COLOR:SetBrightness(amount)
		local h,s,l = ColorToHSL(self)
		l = math.Clamp(amount / 255, 0, 1)
		return HSLToColor(h,s,l)
	end

	---Inverts the color.
	---@return Color
	function COLOR:Invert()
		return Color(255 - self.r,255 - self.g,255 - self.b)
	end

	---Turns the color into a gray-scale.
	---@return Color
	function COLOR:ToGrayscale()
		local n = math.Clamp(math.Round(self.r * .299 + self.g * .587 + self.b * .114), 0, 255)
		return Color(n,n,n)
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
		return NikNaks.ColorToLuminance(self) >= 127.5
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

	---@source https://github.com/ValveSoftware/source-sdk-2013/blob/master/sp/src/utils/vrad/lightmap.cpp#L3551
	---Convert a RGBExp32 to a RGBA8888
	---@param struct table
	---@return Color
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

