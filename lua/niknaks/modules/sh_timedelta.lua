-- Copyright © 2022-2072, Nak, https://steamcommunity.com/id/Nak2/
-- All Rights Reserved. Not allowed to be reuploaded.
-- License: https://github.com/Nak2/NikNaks/blob/main/LICENSE

---@class TimeDelta
---@field time number
---@operator add:TimeDelta|DateTime
---@operator sub:TimeDelta|DateTime
---@operator mul:TimeDelta
---@operator div:TimeDelta
---@operator pow:TimeDelta
---@operator mod:TimeDelta
local meta = {}
meta.__index = meta
meta.MetaName = "TimeDelta"
NikNaks.__metatables["TimeDelta"] = meta

local TimeDelta = {}
TimeDelta.Milisecond = 0.001
TimeDelta.Second = 1
TimeDelta.Minute = 60
TimeDelta.Hour = 3600
TimeDelta.Day = 86400
TimeDelta.Week = 604800
TimeDelta.Year = 31536000
TimeDelta.Decade = 315359654
TimeDelta.Century = 3153596543
TimeDelta._steps = { "Year", "Day", "Hour", "Minute", "Second", "Milisecond" }

setmetatable( TimeDelta, {
	__index = TimeDelta,
	__call = function( _, time )
		return setmetatable( { time = time }, meta )
	end
} )

---@overload fun(number:number) : TimeDelta
NikNaks.TimeDelta = TimeDelta

do
	local abs = math.abs
	local floor = math.floor
	local steps = TimeDelta._steps

	--- Breaks the duration into a table of named time components (Year, Day, Hour, etc.).
	---@return table
	function meta:ToTable()
		if self._tab then return self._tab end

		local t = {}
		local num = abs( self.time )
		local f = self.time < 0 and -1 or 1
		local isLeapYear = NikNaks.DateTime.IsLeapYear

		local function processStep( i )
			local step = steps[i]
			local value = TimeDelta[step]

			-- Leap year
			if num < value then return end

			if i == 1 then -- Since years aren't whole numbers, we need to round the tiniest amount, or floor is going to count down.
				local n = 0
				local y = TimeDelta.Year
				local v = isLeapYear( y ) and 31622400 or 31536000

				while num >= v do
					local q = 1 * f
					if num >= v then
						n = n + 1
						num = num - v
						y = y + q
						v = isLeapYear( y ) and 31622400 or 31536000
					else
						break
					end
				end

				t[step] = n * f
			else
				local n = floor( num / value )
				t[step] = n * f
				num = num - value * n
			end
		end

		for i = 1, #steps do
			processStep( i )
		end

		self._tab = t
		return t
	end
end

-- Getters
do
	--- Returns the total duration expressed in the given time unit (e.g. "Hour", "Minute").
	---@param key string The time unit name to divide by.
	---@return number
	function meta:_getter( key )
		return self.time / TimeDelta[key]
	end

	--- Returns the total duration expressed as a fractional number of milliseconds.
	---@return number
	function meta:GetMiliseconds() return self:_getter( "Milisecond" ) end
	--- Returns the total duration expressed as a fractional number of seconds.
	---@return number
	function meta:GetSeconds() return self:_getter( "Second" ) end
	--- Returns the total duration expressed as a fractional number of minutes.
	---@return number
	function meta:GetMinutes() return self:_getter( "Minute" ) end
	--- Returns the total duration expressed as a fractional number of hours.
	---@return number
	function meta:GetHours() return self:_getter( "Hour" ) end
	--- Returns the total duration expressed as a fractional number of days.
	---@return number
	function meta:GetDays() return self:_getter( "Day" ) end
	--- Returns the total duration expressed as a fractional number of weeks.
	---@return number
	function meta:GetWeeks() return self:_getter( "Week" ) end
	--- Returns the total duration expressed as a fractional number of months.
	---@return number
	function meta:GetMonths() return self:_getter( "Month" ) end
	--- Returns the total duration expressed as a fractional number of years.
	---@return number
	function meta:GetYears() return self:_getter( "Year" ) end
	--- Returns the total duration expressed as a fractional number of decades.
	---@return number
	function meta:GetDecades() return self:_getter( "Decade" ) end
	--- Returns the total duration expressed as a fractional number of centuries.
	---@return number
	function meta:GetCenturies() return self:_getter( "Century" ) end
end

-- Adders
do
	--- Adds the given amount of a time unit to this TimeDelta and invalidates the cached table.
	---@param key string The time unit name (e.g. "Hour", "Day").
	---@param num number The amount to add.
	---@return self
	function meta:_adder( key, num )
		self.time = self.time + ( num * TimeDelta[key] )
		self._tab = nil
		return self
	end

	--- Adds the given number of milliseconds to this TimeDelta.
	---@param n number
	---@return TimeDelta
	function meta:AddMiliseconds( n ) return self:_adder( "Milisecond", n ) end
	--- Adds the given number of seconds to this TimeDelta.
	---@param n number
	---@return TimeDelta
	function meta:AddSeconds( n ) return self:_adder( "Second", n ) end
	--- Adds the given number of minutes to this TimeDelta.
	---@param n number
	---@return TimeDelta
	function meta:AddMinutes( n ) return self:_adder( "Minute", n ) end
	--- Adds the given number of hours to this TimeDelta.
	---@param n number
	---@return TimeDelta
	function meta:AddHours( n ) return self:_adder( "Hour", n ) end
	--- Adds the given number of days to this TimeDelta.
	---@param n number
	---@return TimeDelta
	function meta:AddDays( n ) return self:_adder( "Day", n ) end
	--- Adds the given number of weeks to this TimeDelta.
	---@param n number
	---@return TimeDelta
	function meta:AddWeeks( n ) return self:_adder( "Week", n ) end
	--- Adds the given number of months to this TimeDelta.
	---@param n number
	---@return TimeDelta
	function meta:AddMonths( n ) return self:_adder( "Month", n ) end
	--- Adds the given number of years to this TimeDelta.
	---@param n number
	---@return TimeDelta
	function meta:AddYears( n ) return self:_adder( "Year", n ) end
	--- Adds the given number of decades to this TimeDelta.
	---@param n number
	---@return TimeDelta
	function meta:AddDecades( n ) return self:_adder( "Decade", n ) end
	--- Adds the given number of centuries to this TimeDelta.
	---@param n number
	---@return TimeDelta
	function meta:AddCenturies( n ) return self:_adder( "Century", n ) end
end

-- Subtractors
do
	--- Subtracts the given amount of a time unit from this TimeDelta and invalidates the cached table.
	---@param key string The time unit name (e.g. "Hour", "Day").
	---@param num number The amount to subtract.
	---@return self
	function meta:_subtractor( key, num )
		self.time = self.time - ( num * TimeDelta[key] )
		self._tab = nil
		return self
	end

	--- Subtracts the given number of milliseconds from this TimeDelta.
	---@param n number
	---@return TimeDelta
	function meta:SubMiliseconds( n ) return self:_subtractor( "Milisecond", n ) end
	--- Subtracts the given number of seconds from this TimeDelta.
	---@param n number
	---@return TimeDelta
	function meta:SubSeconds( n ) return self:_subtractor( "Second", n ) end
	--- Subtracts the given number of minutes from this TimeDelta.
	---@param n number
	---@return TimeDelta
	function meta:SubMinutes( n ) return self:_subtractor( "Minute", n ) end
	--- Subtracts the given number of hours from this TimeDelta.
	---@param n number
	---@return TimeDelta
	function meta:SubHours( n ) return self:_subtractor( "Hour", n ) end
	--- Subtracts the given number of days from this TimeDelta.
	---@param n number
	---@return TimeDelta
	function meta:SubDays( n ) return self:_subtractor( "Day", n ) end
	--- Subtracts the given number of weeks from this TimeDelta.
	---@param n number
	---@return TimeDelta
	function meta:SubWeeks( n ) return self:_subtractor( "Week", n ) end
	--- Subtracts the given number of months from this TimeDelta.
	---@param n number
	---@return TimeDelta
	function meta:SubMonths( n ) return self:_subtractor( "Month", n ) end
	--- Subtracts the given number of years from this TimeDelta.
	---@param n number
	---@return TimeDelta
	function meta:SubYears( n ) return self:_subtractor( "Year", n ) end
	--- Subtracts the given number of decades from this TimeDelta.
	---@param n number
	---@return TimeDelta
	function meta:SubDecades( n ) return self:_subtractor( "Decade", n ) end
	--- Subtracts the given number of centuries from this TimeDelta.
	---@param n number
	---@return TimeDelta
	function meta:SubCenturies( n ) return self:_subtractor( "Century", n ) end
end

-- ToString
do
	local abs = math.abs
	local steps = TimeDelta._steps

	--- Returns a human-readable string like "1 Year, 2 Days and 3 Hours".
	function meta:__tostring()
		local str
		local si = 0
		local tab = self:ToTable()
		local kv = #table.GetKeys( tab )

		for i = 1, #steps do
			local step = steps[i]

			if tab[step] then
				si = si + 1

				local number = abs( tab[step] )
				local middle = ( si == kv and " and " or ", " )
				step = number == 1 and step or step .. "s"

				if not str then
					str = number .. " " .. step
				else
					str = str .. middle .. number .. " " .. step
				end
			end
		end

		return str or "nil"
	end
end

--- Returns true if this TimeDelta represents a negative duration.
---@return boolean
function meta:IsNegative()
	return self.time < 0
end

--- Returns true if this TimeDelta represents a zero or positive duration.
---@return boolean
function meta:IsPositive()
	return self.time >= 0
end

-- Operations
do
	--- Adds seconds or a DateTime to this delta. `timedelta + number` returns a new TimeDelta.
	--- `timedelta + DateTime` shifts the DateTime forward and returns a new DateTime.
	---@param b TimeDelta|number
	---@return TimeDelta
	function meta:__add( b )
		if isnumber( b ) then
			return TimeDelta( self.time + b )
		elseif b.time then
			return NikNaks.TimeDelta( b.time + self.time )
		end
	end

	--- Subtracts seconds or a DateTime from this delta. `timedelta - number` returns a new TimeDelta.
	--- `timedelta - DateTime` shifts the DateTime backward by this duration and returns a new DateTime.
	---@param b TimeDelta|number
	---@return TimeDelta
	function meta:__sub( b )
		if isnumber( b ) then
			return TimeDelta( self.time - b )
		elseif b.time then
			return NikNaks.TimeDelta( b.time - self.time )
		end
		return self
	end

	--- Scales the duration by a multiplier.
	---@param b TimeDelta|number
	---@return TimeDelta
	function meta:__mul( b )
		b = isnumber( b ) and b or b.time
		return TimeDelta( self.time * b )
	end

	--- Divides the duration by a divisor.
	---@param b TimeDelta|number
	---@return TimeDelta
	function meta:__div( b )
		b = isnumber( b ) and b or b.time
		return TimeDelta( self.time / b )
	end

	--- Raises the duration in seconds to the given power.
	---@param b TimeDelta|number
	---@return TimeDelta
	function meta:__pow( b )
		b = isnumber( b ) and b or b.time
		return TimeDelta( self.time ^ b )
	end

	--- Returns the remainder of dividing the duration by the given value.
	---@param b TimeDelta|number
	---@return TimeDelta
	function meta:__mod( b )
		b = isnumber( b ) and b or b.time
		return TimeDelta( self.time % b )
	end

	--- Returns true if both TimeDelta values represent the same duration.
	---@param b TimeDelta
	---@return boolean
	function meta:__eq( b )
		return self.time == b.time
	end

	--- Returns true if this duration is strictly shorter than the other.
	---@param b TimeDelta
	---@return boolean
	function meta:__lt( b )
		return self.time < b.time
	end

	--- Returns true if this duration is shorter than or equal to the other.
	---@param b TimeDelta
	---@return boolean
	function meta:__le( b )
		return self.time <= b.time
	end
end
