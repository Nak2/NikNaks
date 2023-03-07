-- Copyright © 2022-2072, Nak, https://steamcommunity.com/id/Nak2/
-- All Rights Reserved. Not allowed to be reuploaded.
-- License: https://github.com/Nak2/NikNaks/blob/main/LICENSE

NikNaks.DateTime = {}
local localvars, os_time, os_date, rawget, tonumber, getmetatable = {}, os.time, os.date, rawget, tonumber, getmetatable

-- TimeZone / Date variables
do
	local UTC_DAY = os_date( "%d", 0 ) - os_date( "!%d", 0 )
	local UTC_Timezone = tonumber( os_date( "%H", 0 ) ) - tonumber( os_date( "!%H", 0 ) )
	if UTC_DAY == 30 then
		UTC_Timezone = UTC_Timezone - 24
	end

	local UTC_Timezone_dst = tonumber( os_date( "%z" ) ) / 100
	local DaylightsSaving = UTC_Timezone_dst - UTC_Timezone
	NikNaks.DateTime.dst = DaylightsSaving
	NikNaks.DateTime.timezone = UTC_Timezone
	NikNaks.DateTime.timezone_dst = UTC_Timezone_dst
end

local function is_leap_year( year )
	return year % 4 == 0 and ( year % 100 ~= 0 or year % 400 == 0 )
end

function NikNaks.DateTime.IsLeapYear( year )
	return is_leap_year( year or NikNaks.DateTime.year )
end

do
	local months = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }

	function NikNaks.DateTime.DaysInMonth( month, year )
		if month == 2 and is_leap_year( year or NikNaks.DateTime.year ) then
			return 29
		end

		return months[month]
	end

	function NikNaks.DateTime.Calender( year )
		year = year or NikNaks.DateTime.year
		local c = {}
		c.year = year
		c.month = {}

		for i = 1, 12 do
			if i == 2 and is_leap_year( year ) then
				c.month[i] = 29
			else
				c.month[i] = months[i]
			end
		end

		return c
	end
end

-- Date variables
local function updatedate()
	local date = string.Explode( ":", os_date( "%H:%M:%S:%d:%m:%Y" ) )
	NikNaks.DateTime.day = tonumber( date[4] )
	NikNaks.DateTime.month = tonumber( date[5] )
	NikNaks.DateTime.year = tonumber( date[6] )

	-- Calculates next cycle
	local t_seconds = tonumber( date[1] ) * 3600 + tonumber( date[2] ) * 60 + tonumber( date[3] )
	local nextUpdate = 86400 - t_seconds
	timer.Create( "NikNaks_DateUpdate", math.max( nextUpdate, 1 ), 1, updatedate )
end
updatedate()

-- Branch metatable
setmetatable( NikNaks.DateTime, {
	__index = function( _, v )
		local l = rawget( localvars, v )
		return rawget( NikNaks.DateTime, v ) or l and l()
	end,
	__call = function( _, var )
		return NikNaks.DateTime.Get( var )
	end
} )

local string_to_var
do
	-- Tries to parse hour, minute and seconds
	local function findTime( str )
		local h, m, s, ampm = string.match( str:upper(), "([01]?%d):(%d%d?):?(%d*)%s*([AP][M])" )

		if not h then
			h, m, s = string.match( str, "(%d%d?):(%d%d?):?(%d*)" )
		end

		if not h then return nil end
		h = tonumber( h )
		m = tonumber( m )
		s = tonumber( s )

		if ampm then
			if ampm == "AM" then
				if h == 12 then h = 0 end
			else
				if h ~= 12 then h = h + 12 end
			end
		end

		return h, m, s
	end

	-- Tries to parse year, month, day
	local findDate
	do
		local date_tab = {
			"JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"
		}

		local date_pattern = "[JFMASOND][AEPUCO][NBRYLGPTVC]"
		local function findMonthNameAndDate( str )
			if not string.match( str, date_pattern ) then return nil end

			for m_id, date in ipairs( date_tab ) do
				if string.match( str, date ) then
					local d = string.match( str, date .. "%a*%s?(%d%d?)" ) or string.match( str, "(%d%d?)%s?" .. date )
					return m_id, d and tonumber( d ) or 1
				end
			end
		end

		function findDate( str )
			-- The year number tent to mess with the rest, if found replace it if found.
			local fy = true
			local y = string.match( str, "(%d%d%d%d)" )
			local m, d
			if y then
				str = string.gsub( str, "%d%d%d%d", "", 1 )
				y = tonumber( y )
			else
				-- Check of YY/MM/DD
				y, m, d = string.match( str, "(%d+)[/%-](%d%d?)[/%-](%d%d?)" )
				if not y then -- Year must be today
					y = NikNaks.DateTime.year
					fy = false
				else
					return tonumber( y ), tonumber( m ), tonumber( d )
				end
			end

			-- Find MM/DD
			m, d = string.match( str, "(%d%d?)[/%-](%d%d?)" )
			if m and d then
				return y, tonumber( m ), tonumber( d )
			end

			-- No date found. Try string-scan for month names
			m, d = findMonthNameAndDate( str:upper() ) -- Try parse letters
			if m then
				return y, m, d
			end

			-- If only a year is given, then return the first day in that year.
			if fy then
				return y, 1, 1
			end
		end
	end

	-- Tries to parse timezone. Since os.time use the locate time, this will be negative.
	local function findOffset( str )
		if str:sub( -1 ) == "Z" then return -NikNaks.DateTime.timezone_dst end
		local sign, h, m = str:match( "([%-%+])(%d%d?):?(%d?%d?)$" )
		if sign then
			return ( tonumber( sign .. h ) + tonumber( sign .. m ) / 60 ) - NikNaks.DateTime.timezone_dst
		else
			-- Use local
			return 0
		end
	end

	function string_to_var( str )
		str = string.Trim( str )

		if #str ~= 4 then
			local n = string.match( str, "%d+" )
			if #n == #str then return tonumber( n ) end
		end

		--[[
			Sun, 03 Jan 2010 00:00:00 GMT
			September 26, 2006 12:12 AM
			2012-10-06T04:13:00+00:00
			2012/10/6
			2008-05-01T07:34:42-5:00
			2008-05-01 7:34:42Z
			Thu, 01 May 2008 07:34:42 GMT
		]]
		local h, m, s = findTime( str )

		-- Get Time & Date
		local year, month, day = findDate( str )

		-- Find offset
		local offsetH = findOffset( str ) or 0

		-- Convert to unix
		return os_time( {
			day = day or 1,
			hour = h or 0,
			min = m or 0,
			month = month or 1,
			sec = tonumber( s ) or 0,
			year = year
		} ) + offsetH * 3600
	end
end

--- @class DateTime
local datetime_obj = {}
datetime_obj.__index = datetime_obj
NikNaks.__metatables["DateTime"] = datetime_obj
function NikNaks.DateTime.Get( var, t_zone )
	if not var then
		var = os_time()
	else
		local _type = type( var )
		if _type == "string" then
			var = string_to_var( var )
		elseif _type == "table" then
			if var.time then
				var = var.time + os_time()
			elseif var.unix then
				var = var.unix
			else -- Unknown
				return nil
			end
		end
	end

	-- Unable to create
	if not var then return nil end

	-- Create object and return
	--- @class DateTime
	local t = {}
	t.unix = var
	t.timezone = t_zone
	return setmetatable( t, datetime_obj )
end

function datetime_obj:GetUnix()
	return self.unix
end

function datetime_obj:TimeUntil( var )
	local unix
	local _type = type( var )

	if _type == "string" then
		unix = string_to_var( var )
	elseif _type == "table" then
		if var.time then
			return var.time -- Will always be relative
		elseif var.unix then
			unix = var.unix
		end
	end

	return NikNaks.TimeDelta( unix - self.unix, tonumber( os.date( "%Y", self.unix ) ) )
end

-- Local variable functions: DateTime.<X>
function localvars.now()
	return NikNaks.DateTime.Get( os_time() )
end
localvars.today = localvars.now

function localvars.yesterday()
	return NikNaks.DateTime.Get( os_time() - NikNaks.TimeDelta.Day )
end

function localvars.tomorrow()
	return NikNaks.DateTime.Get( os_time() + NikNaks.TimeDelta.Day )
end

--- Returns the time using os.date
--- @param format string
--- @return string
function datetime_obj:ToDate( format )
	return os_date( format, self.unix )
end
datetime_obj.__tostring = function( self )
	return os_date( nil, self.unix )
end

-- Operations
function datetime_obj.__sub( a, b )
	if not getmetatable( a ) then -- A is most likely a number. Number - Obj = TimeDelta
		return NikNaks.TimeDelta( a - b.unix )
	elseif not getmetatable( b ) then -- B is most likely a number. Obj - Number = New Obj
		return NikNaks.DateTime.Get( a.unix - b )
	else -- Both are objects
		if a.unix and b.unix then
			return NikNaks.TimeDelta( a.unix - b.unix )
		elseif a.unix then
			return NikNaks.DateTime.Get( a.unix - ( b.time or b ) )
		elseif b.unix then
			return NikNaks.DateTime.Get( b.unix - ( a.time or a ) )
		end
	end
end

function datetime_obj.__add( a, b )
	if not getmetatable( a ) then -- A is most likely a number. Number + Obj = New Obj
		return NikNaks.DateTime.Get( b.unix + a )
	elseif not getmetatable( b ) then -- B is most likely a number. Obj - Number = New Obj
		return NikNaks.DateTime.Get( a.unix + b )
	else -- Both are objects
		if a.unix and b.unix then -- Get the higest unix-time and add the delta between the two
			return NikNaks.DateTime.Get( math.max( a.unix, b.unix ) + abs( a.unix - b.unix ) )
		elseif a.unix then
			return NikNaks.DateTime.Get( a.unix + ( b.time or b ) )
		elseif b.unix then
			return NikNaks.DateTime.Get( b.unix + ( a.time or a ) )
		end
	end
end

function datetime_obj.__concat( a, b )
	return tostring( a ) .. tostring( b )
end

-- Not supported in Gmod!
datetime_obj.__shl = datetime_obj.__sub
datetime_obj.__shr = datetime_obj.__add

-- Sadly Lua doesn't support mixed types for compare-operations
function datetime_obj.__eq( a, b )
	return a.unix == b.unix
end

function datetime_obj.__lt( a, b )
	return a.unix < b.unix
end

function datetime_obj.__le( a, b )
	return a.unix <= b.unix
end

-- TimeDelta functions
for key, var in pairs( NikNaks.TimeDelta ) do
	datetime_obj["Add" .. key .. "s"] = function( self, num )
		self.unix = self.unix + num * var
		return self
	end

	datetime_obj["Remove" .. key .. "s"] = function( self, num )
		self.unix = self.unix - num * var
		return self
	end

	datetime_obj["Sub" .. key .. "s"] = datetime_obj["Remove" .. key .. "s"]
end

-- DateTime string debug test
if true then return end
local t = {	"Sun, 01 Sep 2022 00:12:00",
			"September 01, 2022 12:12 AM",
			"2022-09-01T00:12:00+02:00",
			"2022/09/1",
			"2022-09-01T07:12:00-5:00",
			"2022-09-01 02:12:00Z",
			"Thu, 01 Sep 2022 00:12:00" }

function ParseTest()
	for _, str in ipairs( t ) do
		print( str .. string.rep( " ", 30 - #str ), "=>", NikNaks.DateTime.Get( str ) )
	end
end

function SpeedTest()
	local n = 20000 * #t
	local s = SysTime()

	for _, str in ipairs( t ) do
		for _ = 1, 20000 do
			NikNaks.DateTime.Get( str )
		end
	end

	print( string.format( n .. " took: %fs", SysTime() - s ) )
end
