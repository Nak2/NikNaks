-- Copyright © 2022-2072, Nak, https://steamcommunity.com/id/Nak2/
-- All Rights Reserved. Not allowed to be reuploaded.
-- License: https://github.com/Nak2/NikNaks/blob/main/LICENSE

---Returns a DateTime object.
---@overload fun(var: string|number|DateTime|TimeDelta|nil, t_zone:number|"L"?) : DateTime?
NikNaks.DateTime = {}
local localvars, os_time, os_date, rawget, tonumber, getmetatable, abs = {}, os.time, os.date, rawget, tonumber,
	getmetatable, math.abs

-- TimeZone / Date variables
do
	local UTC_DAY = os_date("%d", 0) - os_date("!%d", 0)
	local UTC_Timezone = tonumber(os_date("%H", 0)) - tonumber(os_date("!%H", 0))
	if UTC_DAY == 30 then
		UTC_Timezone = UTC_Timezone - 24
	end

	local UTC_Timezone_dst = tonumber(os_date("%z")) / 100
	local DaylightsSaving = UTC_Timezone_dst - UTC_Timezone
	NikNaks.DateTime.dst = DaylightsSaving
	NikNaks.DateTime.timezone = UTC_Timezone
	NikNaks.DateTime.timezone_dst = UTC_Timezone_dst
end

local function is_leap_year(year)
	return year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0)
end

--- Returns true if the year is a leap year.
---@param year number
---@return boolean
function NikNaks.DateTime.IsLeapYear(year)
	return is_leap_year(year or NikNaks.DateTime.year)
end

do
	local months = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }

	--- Returns the number of days in the given month, accounting for leap years.
	---@param month number Month index between 1 and 12.
	---@param year number Year used to determine if February has 29 days.
	---@return number
	function NikNaks.DateTime.DaysInMonth(month, year)
		-- Ensure month is within range
		month = math.Clamp(month, 1, 12)
		if month == 2 and is_leap_year(year or NikNaks.DateTime.year) then
			return 29
		end
		return months[month]
	end

	--- Builds a Calendar table with the number of days per month for the given year.
	---@param year number
	---@return Calendar
	function NikNaks.DateTime.Calendar(year)
		year = year or NikNaks.DateTime.year

		---@class Calendar
		---@field year number The calendar year.
		---@field month table<number, number> Days in each month (1–12), accounting for leap years.
		local c = {}
		c.year = year
		c.month = {}

		for i = 1, 12 do
			if i == 2 and is_leap_year(year) then
				c.month[i] = 29
			else
				c.month[i] = months[i]
			end
		end

		return c
	end
end

do
	local floor = math.floor

	local function days_from_civil(y, m, d)
		y = (m <= 2) and (y - 1) or y
		local era = floor((y >= 0 and y or (y - 399)) / 400)
		local yoe = y - era * 400                                                      -- [0, 399]
		local doy = floor((153 * (m + (m > 2 and -3 or 9)) + 2) / 5) + d - 1            -- [0, 365]
		local doe = yoe * 365 + floor(yoe / 4) - floor(yoe / 100) + doy                 -- [0, 146096]
		return era * 146097 + doe - 719468
	end

	local function civil_from_days(z)
		z = z + 719468
		local era = floor((z >= 0 and z or (z - 146096)) / 146097)
		local doe = z - era * 146097                                                    -- [0, 146096]
		local yoe = floor((doe - floor(doe / 1460) + floor(doe / 36524) - floor(doe / 146096)) / 365) -- [0, 399]
		local y = yoe + era * 400
		local doy = doe - (365 * yoe + floor(yoe / 4) - floor(yoe / 100))               -- [0, 365]
		local mp = floor((5 * doy + 2) / 153)                                           -- [0, 11]
		local d = doy - floor((153 * mp + 2) / 5) + 1                                   -- [1, 31]
		local m = mp + (mp < 10 and 3 or -9)                                            -- [1, 12]
		return y + ((m <= 2) and 1 or 0), m, d
	end

	--- Converts to a Unix timestamp (seconds).
	---@param year number
	---@param month number? 1-12. Default 1.
	---@param day number? 1-31. Default 1.
	---@param hour number? Default 0.
	---@param min number? Default 0.
	---@param sec number? Default 0.
	---@return number
	function NikNaks.DateTime.ToUnix(year, month, day, hour, min, sec)
		local days = days_from_civil(year, month or 1, day or 1)
		return days * 86400 + (hour or 0) * 3600 + (min or 0) * 60 + (sec or 0)
	end

	--- Breaks a Unix timestamp down into its calendar components.
	---@param unix number
	---@return table # {year, month, day, hour, min, sec, wday} -- wday: 1=Sunday..7=Saturday, matching os.date("*t").wday
	function NikNaks.DateTime.Components(unix)
		unix = unix >= 0 and floor(unix) or -floor(-unix)

		local days = floor(unix / 86400)
		local rem = unix - days * 86400
		local year, month, day = civil_from_days(days)
		local hour = floor(rem / 3600); rem = rem - hour * 3600
		local min = floor(rem / 60); local sec = rem - min * 60
		local wday = ((days + 4) % 7 + 7) % 7 + 1 -- 1970-01-01 (days=0) was a Thursday (wday 5)
		return { year = year, month = month, day = day, hour = hour, min = min, sec = sec, wday = wday }
	end
end

local manual_format
do
	local month_names = { "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December" }
	local day_names = { "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" }

	---@param format string?
	---@param unix number
	---@param offsetHours number? The DateTime's displayed timezone offset, used only for the %z token.
	function manual_format(format, unix, offsetHours)
		local c = NikNaks.DateTime.Components(unix)

		-- string.gsub returns (result, count) -- parenthesize to drop the
		-- count, otherwise callers doing e.g. tonumber(dt:ToDate(...)) would
		-- silently receive it as tonumber's second (base) argument.
		return ((format or "%Y-%m-%d %H:%M:%S"):gsub("%%(.)", function(f)
			if f == "Y" then return tostring(c.year)
			elseif f == "y" then return string.format("%02d", c.year % 100)
			elseif f == "m" then return string.format("%02d", c.month)
			elseif f == "d" then return string.format("%02d", c.day)
			elseif f == "e" then return string.format("%2d", c.day)
			elseif f == "H" then return string.format("%02d", c.hour)
			elseif f == "I" then
				local h12 = c.hour % 12
				return string.format("%02d", h12 == 0 and 12 or h12)
			elseif f == "M" then return string.format("%02d", c.min)
			elseif f == "S" then return string.format("%02d", c.sec)
			elseif f == "p" then return c.hour < 12 and "AM" or "PM"
			elseif f == "A" then return day_names[c.wday]
			elseif f == "a" then return day_names[c.wday]:sub(1, 3)
			elseif f == "w" then return tostring(c.wday - 1) -- 0=Sunday..6=Saturday
			elseif f == "B" then return month_names[c.month]
			elseif f == "b" then return month_names[c.month]:sub(1, 3)
			elseif f == "j" then
				local yearStart = NikNaks.DateTime.ToUnix(c.year, 1, 1, 0, 0, 0)
				return string.format("%03d", math.floor((unix - yearStart) / 86400) + 1)
			elseif f == "n" then return "\n"
			elseif f == "t" then return "\t"
			elseif f == "z" then
				local oh = offsetHours or 0
				local totalMin = math.floor(math.abs(oh) * 60 + 0.5)
				return string.format("%s%02d%02d", oh < 0 and "-" or "+", math.floor(totalMin / 60), totalMin % 60)
			elseif f == "c" then return manual_format("%a %b %e %H:%M:%S %Y", unix, offsetHours)
			elseif f == "x" then return manual_format("%m/%d/%y", unix, offsetHours)
			elseif f == "X" then return manual_format("%H:%M:%S", unix, offsetHours)
			elseif f == "%" then return "%"
			else return "%" .. f end
		end))
	end
end

local function updatedate()
	local c = NikNaks.DateTime.Components(os_time() + (NikNaks.DateTime.timezone_dst or 0) * 3600)
	NikNaks.DateTime.day = c.day
	NikNaks.DateTime.month = c.month
	NikNaks.DateTime.year = c.year

	-- Calculates next cycle
	local t_seconds = c.hour * 3600 + c.min * 60 + c.sec
	local nextUpdate = 86400 - t_seconds
	timer.Create("NikNaks_DateUpdate", math.max(nextUpdate, 1), 1, updatedate)
end
updatedate()

-- Branch metatable
setmetatable(NikNaks.DateTime --[[@as table]], {
	__index = function(_, v)
		local l = rawget(localvars, v)
		return rawget(NikNaks.DateTime --[[@as table]], v) or l and l()
	end,
	__call = function(_, var, t_zone)
		return NikNaks.DateTime.Get(var, t_zone)
	end
})

--- The current date and time.
---@type DateTime
NikNaks.DateTime.now = nil

--- Midnight of the current day.
---@type DateTime
NikNaks.DateTime.today = nil

--- Midnight of the previous day.
---@type DateTime
NikNaks.DateTime.yesterday = nil

--- Midnight of the next day.
---@type DateTime
NikNaks.DateTime.tomorrow = nil

local string_to_var
do
	-- Tries to parse hour, minute and seconds
	local function findTime(str)
		local h, m, s, ampm = string.match(str:upper(), "([01]?%d):(%d%d?):?(%d*)%s*([AP][M])")

		if not h then
			h, m, s = string.match(str, "(%d%d?):(%d%d?):?(%d*)")
		end

		if not h then return end
		h = tonumber(h) --[[@as number]]
		m = tonumber(m) or 0
		s = tonumber(s) or 0

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
		local function findMonthNameAndDate(str)
			if not string.match(str, date_pattern) then return nil end

			for m_id, date in ipairs(date_tab) do
				if string.match(str, date) then
					local d = string.match(str, date .. "%a*%s?(%d%d?)") or string.match(str, "(%d%d?)%s?" .. date)
					return m_id, d and tonumber(d) or 1
				end
			end
		end

		---Tries to parse a given string for a date.
		---@param str string
		---@return number? Year The year
		---@return number? Month The month
		---@return number? Day The day
		findDate = function(str)
			local fy = true
			local y = string.match(str, "^([%+%-]%d%d%d%d+)") or string.match(str, "(%d%d%d%d+)")
			local m, d
			if y then
				str = string.gsub(str, "^[%+%-]%d%d%d%d+", "", 1)
				str = string.gsub(str, "%d%d%d%d+", "", 1)
				y = tonumber(y)
			else
				-- Check of YY/MM/DD
				y, m, d = string.match(str, "(%d+)[/%-](%d%d?)[/%-](%d%d?)")
				if not y then -- Year must be today
					y = NikNaks.DateTime.year
					fy = false
				else
					return tonumber(y), tonumber(m), tonumber(d)
				end
			end

			-- Find MM/DD
			m, d = string.match(str, "(%d%d?)[/%-](%d%d?)")
			if m and d then
				return y, tonumber(m), tonumber(d)
			end

			-- No date found. Try string-scan for month names
			m, d = findMonthNameAndDate(str:upper()) -- Try parse letters
			if m then
				return y, m, d
			end

			-- If only a year is given, then return the first day in that year.
			if fy then
				return y, 1, 1
			end

			-- No date info found
			return y, NikNaks.DateTime.month, NikNaks.DateTime.day
		end
	end

	-- Returns the offset (in hours) explicitly carried by the string, or nil
	local function findOffset(str)
		if str:sub(-1) == "Z" then return 0 end
		if str:upper():match("GMT$") or str:upper():match("UTC$") then return 0 end
		local sign, h, m = str:match("([%-%+])(%d%d?):?(%d?%d?)$")
		if sign then
			-- m can match an empty string (e.g. "+0", "-5" with no :MM part), and
			-- tonumber(sign .. "") is nil -- guard instead of crashing on nil/60.
			local mNum = tonumber(sign .. m)
			return tonumber(sign .. h) + (mNum and mNum / 60 or 0)
		end
		return nil
	end

	local function looksLikeDateOrTime(str)
		return str:find("%d") ~= nil or str:upper():find("[JFMASOND][AEPUCO][NBRYLGPTVC]") ~= nil
	end

	---Parses a string into a literal (zone-less) unix value plus whatever
	---offset, if any, the string itself carried.
	---@param str string
	---@return number? literalUnix nil if unparseable.
	---@return number|false|nil stringOffset The offset (hours) found in the string, false if `literalUnix` is already a fully-resolved absolute unix number (the bare-digits shortcut) needing no further zone resolution, or nil if the string carried no recognizable offset.
	function string_to_var(str)
		str = string.Trim(str)

		if not looksLikeDateOrTime(str) then
			return nil
		end

		if #str ~= 4 then
			local n = string.match(str, "%d+")
			if n and #n == #str then return tonumber(n), false end
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
		local h, m, s = findTime(str)

		-- Get Time & Date
		local year, month, day = findDate(str)
		local stringOffset = h and findOffset(str) or nil

		local literalUnix = NikNaks.DateTime.ToUnix(year or NikNaks.DateTime.year, month or 1, day or 1, h or 0, m or 0, s or 0)
		return literalUnix, stringOffset
	end
end

---@class DateTime A fixed point in time represented as a Unix timestamp.
---@field unix number The Unix timestamp in seconds.
---@field timezone number|"err" The UTC offset in hours used for display. When `isLocal` is true this is deliberately the non-number sentinel "err" instead of a snapshot -- isLocal always takes priority, and reading `.timezone` directly here is a bug (use displayTimezone()/zoneArg() internally, or ToDate()/ToOffset() from outside). Only meaningful as a number when `isLocal` is falsy.
---@field isLocal boolean? True if this DateTime always displays at whatever the local system's current timezone is, rather than a fixed offset -- set via t_zone = "L" (e.g. DateTime(var, "L"), FromComponents(..., "L")) or DateTime:ToLocal().
local datetime_obj = {}
datetime_obj.__index = datetime_obj
NikNaks.__metatables["DateTime"] = datetime_obj

local function displayTimezone(self)
	return self.isLocal and NikNaks.DateTime.timezone_dst or (self.timezone or 0)
end

local function zoneArg(self)
	return self.isLocal and "L" or self.timezone
end

---@class DateTimeComponentsInput
---@field year number
---@field month number?
---@field day number?
---@field hour number?
---@field min number?
---@field sec number?

---Returns a DateTime object.
---
--- t_zone priority:
---  - no t_zone, no offset in string	-> Use local timezone.
---  - no t_zone, offset in string		-> Use the string's own offset
---  - t_zone given						-> Use given timezone
---  - t_zone given + offset in string	-> Use given timezone
---@param var string|number|DateTime|TimeDelta|DateTimeComponentsInput|nil The time to convert. If a number, it is treated as a Unix timestamp. A table with a `year` field is treated as calendar components (see FromComponents).
---@param t_zone number|"L"? UTC offset in hours, or "L" for the local system's current timezone (also the default when omitted).
---@return DateTime?
function NikNaks.DateTime.Get(var, t_zone)
	local isLocal = t_zone == "L" or t_zone == nil
	local numericTZone = isLocal and NikNaks.DateTime.timezone_dst or t_zone --[[@as number]]

	if not var then
		var = os_time()
	else
		local _type = type(var)
		if _type == "string" then
			local literalUnix, stringOffset = string_to_var(var)
			if literalUnix == nil then
				return nil
			elseif stringOffset == false then
				var = literalUnix -- already a resolved absolute unix number (bare-digits shortcut)
			else
				local effectiveOffset = stringOffset or numericTZone
				var = literalUnix - effectiveOffset * 3600
				if t_zone == nil and stringOffset then
					t_zone = stringOffset
					isLocal = false
				end
			end
		elseif _type == "table" then
			if var.time then
				var = var.time + os_time()
			elseif var.unix then
				var = var.unix
			elseif var.year then
				var = NikNaks.DateTime.ToUnix(var.year, var.month, var.day, var.hour, var.min, var.sec) - numericTZone * 3600
			else -- Unknown
				return nil
			end
		elseif _type ~= "number" then
			return nil
		end
	end

	-- Unable to create
	if not var then return nil end

	-- Create object and return
	---@class DateTime
	local t = {}
	t.unix = var
	if isLocal then
		t.isLocal = true
	else
		t.timezone = t_zone --[[@as number]]
	end
	return setmetatable(t, datetime_obj)
end

--- Constructs a DateTime directly from calendar components.
---@param year number
---@param month number? 1-12. Default 1.
---@param day number? 1-31. Default 1.
---@param hour number? Default 0.
---@param min number? Default 0.
---@param sec number? Default 0.
---@param t_zone number|"L"? UTC offset in hours to associate with this DateTime, or "L" for the local system's current timezone (see DateTime.Get).
---@return DateTime?
function NikNaks.DateTime.FromComponents(year, month, day, hour, min, sec, t_zone)
	return NikNaks.DateTime.Get({ year = year, month = month, day = day, hour = hour, min = min, sec = sec }, t_zone)
end

---@class DateTimeSerialized
---@field unix number
---@field timezone number|"L"

--- Reconstructs a DateTime from a table produced by DateTime:Serialize(). A `timezone`
--- of "L" (see DateTime.Get) resolves against whatever machine calls Deserialize.
---@param data DateTimeSerialized?
---@return DateTime?
function NikNaks.DateTime.Deserialize(data)
	if not data or type(data) ~= "table" or type(data.unix) ~= "number" then return nil end
	return NikNaks.DateTime.Get(data.unix, data.timezone)
end

--- Returns the Unix timestamp in seconds.
---@return number
function datetime_obj:GetUnix()
	return self.unix
end

--- Serializes this DateTime into a plain table.
---@return DateTimeSerialized
function datetime_obj:Serialize()
	if self.isLocal then
		return { unix = self.unix, timezone = "L" }
	end
	return { unix = self.unix, timezone = self.timezone }
end

--- Returns a new DateTime displayed at a different timezone offset.
---@param hours number UTC offset in hours to display this DateTime at.
---@return DateTime
function datetime_obj:ToOffset(hours)
	return NikNaks.DateTime.Get(self.unix, hours) --[[@as DateTime]]
end

--- Returns a new DateTime for the same instant, displayed in UTC (offset 0).
---@return DateTime
function datetime_obj:ToUTC()
	return self:ToOffset(0)
end

--- Returns a new DateTime for the same instant, displayed in the local system timezone.
---@return DateTime
function datetime_obj:ToLocal()
	return NikNaks.DateTime.Get(self.unix, "L") --[[@as DateTime]]
end

-- Calendar-aware month/year addition
---@param self DateTime
---@param deltaMonths number
---@return DateTime
local function addCalendarMonths(self, deltaMonths)
	local tz = displayTimezone(self)
	local c = NikNaks.DateTime.Components(self.unix + tz * 3600)
	local totalMonths = (c.year * 12 + (c.month - 1)) + deltaMonths
	local newYear = math.floor(totalMonths / 12)
	local newMonth = totalMonths % 12 + 1
	local newDay = math.min(c.day, NikNaks.DateTime.DaysInMonth(newMonth, newYear))
	local unix = NikNaks.DateTime.ToUnix(newYear, newMonth, newDay, c.hour, c.min, c.sec) - tz * 3600
	return NikNaks.DateTime.Get(unix, zoneArg(self)) --[[@as DateTime]]
end

--- Returns a new DateTime with the given number of whole/fractional seconds added.
---@param seconds number
---@return DateTime
function datetime_obj:AddSeconds(seconds)
	return NikNaks.DateTime.Get(self.unix + seconds, zoneArg(self)) --[[@as DateTime]]
end

---@param minutes number
---@return DateTime
function datetime_obj:AddMinutes(minutes)
	return self:AddSeconds(minutes * 60)
end

---@param hours number
---@return DateTime
function datetime_obj:AddHours(hours)
	return self:AddSeconds(hours * 3600)
end

---@param days number
---@return DateTime
function datetime_obj:AddDays(days)
	return self:AddSeconds(days * 86400)
end

--- Calendar-aware, Adds calendar months, clamping the day-of-month if the target month is
--- shorter (e.g. Jan 31 + 1 month = Feb 28).
---@param months number
---@return DateTime
function datetime_obj:AddMonths(months)
	return addCalendarMonths(self, months)
end

--- Calendar-aware, Adds calendar years, clamping Feb 29 to Feb 28 in a non-leap target year.
---@param years number
---@return DateTime
function datetime_obj:AddYears(years)
	return addCalendarMonths(self, years * 12)
end

--- Returns the year
---@return number
function datetime_obj:GetYear() return tonumber(self:ToDate("%Y")) --[[@as number]] end

--- Returns the month (1-12).
---@return number 1-12.
function datetime_obj:GetMonth() return tonumber(self:ToDate("%m")) --[[@as number]] end

--- Returns the day of the month (1-31).
---@return number 1-31.
function datetime_obj:GetDay() return tonumber(self:ToDate("%d")) --[[@as number]] end

--- Returns the hour (0-23).
---@return number 0-23.
function datetime_obj:GetHour()	return tonumber(self:ToDate("%H")) --[[@as number]] end

--- Returns the hour in 12-hour format (1-12).
---@return number 1-12.
function datetime_obj:GetHour12() return (tonumber(self:ToDate("%I")) --[[@as number]]) end

--- Returns "AM" or "PM" depending on the hour.
---@return string "AM" or "PM".
function datetime_obj:GetAMPM() return self:ToDate("%p") end

--- Returns the minute (0-59).
---@return number 0-59.
function datetime_obj:GetMinute() return tonumber(self:ToDate("%M")) --[[@as number]] end

--- Returns the second (0-59).
---@return number 0-59.
function datetime_obj:GetSecond() return tonumber(self:ToDate("%S")) --[[@as number]] end

--- Returns the day of the week as a number, 0=Sunday..6=Saturday.
---@return number Weekday as a number, 0=Sunday..6=Saturday.
function datetime_obj:GetDayOfWeek() return tonumber(self:ToDate("%w")) --[[@as number]] end

--- Returns the day of the year as a number, 1-366.
---@return number Day of the year, 1-366.
function datetime_obj:GetDayOfYear() return tonumber(self:ToDate("%j")) --[[@as number]] end

--- Returns a new DateTime set to midnight of its timezone.
--- @return DateTime
function datetime_obj:GetDate()
	local tz = displayTimezone(self)
	local c = NikNaks.DateTime.Components(self.unix + tz * 3600)
	local unix = NikNaks.DateTime.ToUnix(c.year, c.month, c.day, 0, 0, 0) - tz * 3600
	return NikNaks.DateTime.Get(unix, zoneArg(self)) --[[@as DateTime]]
end

--- Returns the time elapsed since midnight of this DateTime's displayed, 0 - 86399 seconds.
---@return TimeDelta
function datetime_obj:GetTimeOfDay()
	local c = NikNaks.DateTime.Components(self.unix + displayTimezone(self) * 3600)
	return NikNaks.TimeDelta(c.hour * 3600 + c.min * 60 + c.sec)
end

--- Returns the difference between this DateTime and the given time.
---@param var string|number|DateTime|TimeDelta
---@return TimeDelta
function datetime_obj:TimeUntil(var)
	local unix = var --[[@as string|number|DateTime|TimeDelta|nil]]
	if isstring(var) then
		local dt = NikNaks.DateTime.Get(var)
		unix = dt and dt.unix
	elseif istable(var) then
		if var.time then
			---@cast var TimeDelta
			return NikNaks.TimeDelta(var.time)
		elseif var.unix then
			---@cast var DateTime
			unix = var.unix
		end
	end
	---@cast unix number
	return NikNaks.TimeDelta(unix - self.unix, NikNaks.DateTime.Components(self.unix).year)
end

--- Returns the current local time as a DateTime object.
---@return DateTime
function localvars.now()
	return NikNaks.DateTime.Get(os_time(), "L") --[[@as DateTime]]
end

--- Returns the current local date at midnight as a DateTime object.
---@return DateTime
function localvars.today()
	local unix = NikNaks.DateTime.ToUnix(NikNaks.DateTime.year, NikNaks.DateTime.month, NikNaks.DateTime.day, 0, 0, 0)
		- NikNaks.DateTime.timezone_dst * 3600
	return NikNaks.DateTime.Get(unix, "L") --[[@as DateTime]]
end

--- Returns the local date of yesterday at midnight as a DateTime object.
---@return DateTime
function localvars.yesterday()
	return localvars.today() - NikNaks.TimeDelta.Day
end

--- Returns the local date of tomorrow at midnight as a DateTime object.
---@return DateTime
function localvars.tomorrow()
	return localvars.today() + NikNaks.TimeDelta.Day
end

--- Formats the DateTime using the given format string.
---@param format string
---@return string
function datetime_obj:ToDate(format)
	local tz = displayTimezone(self)
	return manual_format(format, self.unix + tz * 3600, tz)
end

--- Formats as RFC 1123 (HTTP-date style), e.g. "Tue, 15 Sep 2026 19:14:26 +0200".
---@return string
function datetime_obj:ToRFC1123()
	local tz = displayTimezone(self)
	return manual_format("%a, %d %b %Y %H:%M:%S", self.unix + tz * 3600, tz)
		.. " " .. (tz == 0 and "GMT" or manual_format("%z", 0, tz))
end

--- Formats as ISO 8601 / RFC 3339, e.g. "2026-09-15T19:14:26+02:00".
---@return string
function datetime_obj:ToISO8601()
	local tz = displayTimezone(self)
	local base = manual_format("%Y-%m-%dT%H:%M:%S", self.unix + tz * 3600, tz)
	if tz == 0 then return base .. "Z" end
	local totalMin = math.floor(math.abs(tz) * 60 + 0.5)
	return base .. string.format("%s%02d:%02d", tz < 0 and "-" or "+", math.floor(totalMin / 60), totalMin % 60)
end

datetime_obj.__tostring = datetime_obj.ToISO8601

function datetime_obj.__sub(a, b)
	if isnumber(a) then    -- A is most likely a number. Number - Obj = TimeDelta
		return NikNaks.TimeDelta(a - b.unix)
	elseif isnumber(b) then -- B is most likely a number. Obj - Number = New Obj
		return NikNaks.DateTime.Get(a.unix - b, zoneArg(a))
	else                   -- Both are objects
		if a.unix and b.unix then
			return NikNaks.TimeDelta(a.unix - b.unix)
		elseif a.unix then
			return NikNaks.DateTime.Get(a.unix - (b.time or b), zoneArg(a))
		elseif b.unix then
			return NikNaks.DateTime.Get(b.unix - (a.time or a), zoneArg(b))
		end
	end
end

function datetime_obj.__add(a, b)
	if isnumber(a) then     -- A is most likely a number. Number + Obj = New Obj
		return NikNaks.DateTime.Get(b.unix + a, zoneArg(b))
	elseif isnumber(b) then -- B is most likely a number. Obj - Number = New Obj
		return NikNaks.DateTime.Get(a.unix + b, zoneArg(a))
	else                    -- Both are objects
		if a.unix and b.unix then -- Get the higest unix-time and add the delta between the two
			return NikNaks.DateTime.Get(math.max(a.unix, b.unix) + abs(a.unix - b.unix), zoneArg(a) or zoneArg(b))
		elseif a.unix then
			return NikNaks.DateTime.Get(a.unix + (b.time or b), zoneArg(a))
		elseif b.unix then
			return NikNaks.DateTime.Get(b.unix + (a.time or a), zoneArg(b))
		end
	end
end

function datetime_obj.__concat(a, b)
	return tostring(a) .. tostring(b)
end

function datetime_obj.__eq(a, b)
	return a.unix == b.unix and b.unix
end

function datetime_obj.__lt(a, b)
	return b.unix and a.unix < b.unix or false
end

function datetime_obj.__le(a, b)
	return b.unix and a.unix <= b.unix or false
end

--- Adds the specified number of milliseconds to the DateTime object.
---@param milliseconds number
---@return DateTime
function datetime_obj:AddMiliseconds(milliseconds)
	return self:AddSeconds(milliseconds / 1000)
end

--- Adds the specified number of weeks to the DateTime object.
---@param weeks number
---@return DateTime
function datetime_obj:AddWeeks(weeks)
	return self:AddDays(weeks * 7)
end

--- Calendar-aware, like AddYears (10 real years, not a flat 3650-day span).
---@param decades number
---@return DateTime
function datetime_obj:AddDecades(decades)
	return self:AddYears(decades * 10)
end

--- Calendar-aware, like AddYears (100 real years, not a flat 36500-day span).
---@param centuries number
---@return DateTime
function datetime_obj:AddCenturies(centuries)
	return self:AddYears(centuries * 100)
end
