-- Copyright © 2022-2072, Nak, https://steamcommunity.com/id/Nak2/
-- All Rights Reserved. Not allowed to be reuploaded.
-- License: https://github.com/Nak2/NikNaks/blob/main/LICENSE

--- @class TimeDelta
--- @operator add:TimeDelta|DateTime
--- @operator sub:TimeDelta|DateTime
--- @operator mul:TimeDelta
--- @operator div:TimeDelta
--- @operator pow:TimeDelta
--- @operator mod:TimeDelta
local meta = {}
meta.__index = meta
meta.MetaName = "TimeDelta"
NikNaks.__metatables["TimeDelta"] = meta

--- @class TimeDeltaModule
--- @operator call:TimeDelta 
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

NikNaks.TimeDelta = TimeDelta


do
	local abs = math.abs
	local floor = math.floor
	local steps = TimeDelta._steps

	--- Returns the time as a table
	--- @return table
	function meta:ToTable()
		if self._tab then return self._tab end

		local t = {}
		local num = abs( self.time )
		local f = self.time < 0 and -1 or 1
		local isLeapYear = NikNaks.DateTime.IsLeapYear

		local function processStep( i )
			local step = steps[i]
			local value = steps[step]

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

				t[s] = n * f
			else
				local n = floor( num / v )
				t[s] = n * f
				num = num - v * n
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
	--- Generic getter function to get the time amount of the given time type
	--- @param key string The name of the time type to get
	--- @return number
	function meta:_getter( key )
		return self.time / TimeDelta[key]
	end

	function meta:GetMiliseconds() return self:_getter( "Milisecond" ) end
	function meta:GetSeconds() return self:_getter( "Second" ) end
	function meta:GetMinutes() return self:_getter( "Minute" ) end
	function meta:GetHours() return self:_getter( "Hour" ) end
	function meta:GetDays() return self:_getter( "Day" ) end
	function meta:GetWeeks() return self:_getter( "Week" ) end
	function meta:GetMonths() return self:_getter( "Month" ) end
	function meta:GetYears() return self:_getter( "Year" ) end
	function meta:GetDecades() return self:_getter( "Decade" ) end
	function meta:GetCenturies() return self:_getter( "Century" ) end
end

-- Adders
do
	--- Generic adder function to add given time amount to the TimeDelta
	--- @param key string The name of the time type to add
	--- @param num number The amount of time to add
	--- @return self TimeDelta
	function meta:_adder( key, num )
		self.time = self.time + ( num * TimeDelta[key] )
		self._tab = nil
		return self
	end

	--- @param n number
	function meta:AddMiliseconds( n ) return self:_adder( "Milisecond", n ) end --- @param n number
	function meta:AddSeconds( n ) return self:_adder( "Second", n ) end         --- @param n number
	function meta:AddMinutes( n ) return self:_adder( "Minute", n ) end         --- @param n number
	function meta:AddHours( n ) return self:_adder( "Hour", n ) end             --- @param n number
	function meta:AddDays( n ) return self:_adder( "Day", n ) end               --- @param n number
	function meta:AddWeeks( n ) return self:_adder( "Week", n ) end             --- @param n number
	function meta:AddMonths( n ) return self:_adder( "Month", n ) end           --- @param n number
	function meta:AddYears( n ) return self:_adder( "Year", n ) end             --- @param n number
	function meta:AddDecades( n ) return self:_adder( "Decade", n ) end         --- @param n number
	function meta:AddCenturies( n ) return self:_adder( "Century", n ) end      --- @param n number
end

-- Subtractors
do
	--- Generic subtractor function to subtract given time amount from the TimeDelta
	--- @param key string The name of the time type to subtract
	--- @param num number The amount of time to subtract
	--- @return self TimeDelta
	function meta:_subtractor( key, num )
		self.time = self.time - ( num * TimeDelta[key] )
		self._tab = nil
		return self
	end

	function meta:SubMiliseconds( n ) return self:_subtractor( "Milisecond", n ) end --- @param n number
	function meta:SubSeconds( n ) return self:_subtractor( "Second", n ) end         --- @param n number
	function meta:SubMinutes( n ) return self:_subtractor( "Minute", n ) end         --- @param n number
	function meta:SubHours( n ) return self:_subtractor( "Hour", n ) end             --- @param n number
	function meta:SubDays( n ) return self:_subtractor( "Day", n ) end               --- @param n number
	function meta:SubWeeks( n ) return self:_subtractor( "Week", n ) end             --- @param n number
	function meta:SubMonths( n ) return self:_subtractor( "Month", n ) end           --- @param n number
	function meta:SubYears( n ) return self:_subtractor( "Year", n ) end             --- @param n number
	function meta:SubDecades( n ) return self:_subtractor( "Decade", n ) end         --- @param n number
	function meta:SubCenturies( n ) return self:_subtractor( "Century", n ) end      --- @param n number
end

-- ToString
do
	local abs = math.abs
	local steps = TimeDelta._steps

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

function meta:IsNegative()
	return self.time < 0
end

function meta:IsPositive()
	return self.time >= 0
end

-- Operations
do
	--- @param b TimeDelta|number
	--- @return TimeDelta|DateTime
	function meta:__add( b )
		if isnumber( b ) then
			return TimeDelta( self.time + b )
		end

		if self.unix and b.time then
			return NikNaks.DateTime( self.unix + b.time )
		elseif b.unix and self.time then
			return NikNaks.DateTime( b.unix + self.time )
		end
	end

	--- @param b TimeDelta|number
	--- @return TimeDelta|DateTime
	function meta:__sub( b )
		if isnumber( b ) then
			return TimeDelta( self.time - b )
		end

		if self.unix and b.time then
			return NikNaks.DateTime( self.unix - b.time )
		elseif b.unix and self.time then
			return NikNaks.DateTime( b.unix - self.time )
		end
	end

	--- @param b TimeDelta|number
	--- @return TimeDelta
	function meta:__mul( b )
		b = isnumber( b ) and b or b.time
		return TimeDelta( self.time * b )
	end

	--- @param b TimeDelta|number
	--- @return TimeDelta
	function meta:__div( b )
		b = isnumber( b ) and b or b.time
		return TimeDelta( self.time / b )
	end

	--- @param b TimeDelta|number
	--- @return TimeDelta
	function meta:__pow( b )
		b = isnumber( b ) and b or b.time
		return TimeDelta( self.time ^ b )
	end

	--- @param b TimeDelta|number
	--- @return TimeDelta
	function meta:__mod( b )
		b = isnumber( b ) and b or b.time
		return TimeDelta( self.time % b )
	end

	--- @param b TimeDelta
	function meta:__eq( b )
		return self.time == b.time
	end

	--- @param b TimeDelta
	function meta:__lt( b )
		return a.time < b.time
	end

	--- @param b TimeDelta
	function meta.__le( b )
		return a.time <= b.time
	end
end
