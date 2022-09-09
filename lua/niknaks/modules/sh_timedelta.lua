-- Copyright © 2022-2072, Nak, https://steamcommunity.com/id/Nak2/
-- All Rights Reserved. Not allowed to be reuploaded.
-- License: https://github.com/Nak2/NikNaks/blob/main/LICENSE

-- TimeDelata
NikNaks.TimeDelta = {}
NikNaks.TimeDelta.Milisecond = 0.001
NikNaks.TimeDelta.Second = 1
NikNaks.TimeDelta.Minute = 60
NikNaks.TimeDelta.Hour = 3600
NikNaks.TimeDelta.Day = 86400
NikNaks.TimeDelta.Week = 604800
NikNaks.TimeDelta.Year = 31535965
NikNaks.TimeDelta.Decade = 315359654
NikNaks.TimeDelta.Century = 3153596543

local meta, tab = {}, {}
meta.__index = meta
meta.MetaName = "TimeDelta"
NikNaks.__metatables["TimeDelta"] = meta

do
	local floor, q, abs = math.floor, {"year", "day", "hour","minute", "second", "milisecond"}, math.abs
	--- Returns the time as a table
	---@return table
	function meta:ToTable()
		if self._tab then return self._tab end
		local t, num, f = {}, abs(self.time), self.time < 0 and -1 or 1
		for i = 1, #q do
			local s = q[i]
			local v = tab[s]
			if num < v then continue end
			local n = floor( num / v )
			t[s] = n * f
			num = num - v * n
		end
		self._tab = t
		return t
	end
end

-- Create tab[<X>], Get<X> and Set<X>
for key, var in pairs( NikNaks.TimeDelta ) do
	local low = key:lower()
	meta["Get" .. key .. "s"] = function(self)
		return self:ToTable()[low] or 0
	end

	meta["Add" .. key .. "s"] = function(self, num)
		self.time = self.time + num * var
		self._tab = nil
		return self
	end

	meta["Remove" .. key .. "s"] = function(self, num)
		self.time = self.time - num * var
		self._tab = nil
		return self
	end
	meta["Sub" .. key .. "s"] = meta["Remove" .. key .. "s"]

	tab[low] = var
end

NikNaks.TimeDelta.__index = NikNaks.TimeDelta
setmetatable(NikNaks.TimeDelta, {__call = function(_, num)
	local t = {}
	t.time = num
	setmetatable(t, meta)
	return t
end})

-- ToString
do
	local q, abs = {"year", "day", "hour","minute", "second", "milisecond"}, math.abs
	function meta:__tostring()
		local tab = self:ToTable()
		local kv, str = #table.GetKeys(tab)
		local si = 0
		for i = 1, #q do
			local time_type = q[i]
			if not tab[time_type] then continue end
			si = si + 1
			local number, middle = abs(tab[time_type]), (si == kv and " and " or ", ")
			time_type = number == 1 and time_type or time_type.."s"
			if not str then
				str = number .. " " .. time_type
			else
				str = str .. middle .. number .. " " .. time_type
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
	function meta.__add(a, b)
		if not getmetatable(a) then -- A is most likely a number
			local t = {}
			t.time = b.time + a
			setmetatable(t, meta)
			return t
		elseif not getmetatable(b) then -- B is most likely a number
			local t = {}
			t.time = a.time + b
			setmetatable(t, meta)
			return t
		else -- Both is a form of an object
			if a.unix and b.time then
				return NikNaks.DateTime(a.unix + b.time)
			elseif b.unix and a.time then
				return NikNaks.DateTime(b.unix + a.time)
			else
				local t = {}
				t.time = (a.time or a) + (b.time or b)
				setmetatable(t, meta)
				return t
			end
		end
	end

	function meta.__sub(a, b)
		if not getmetatable(a) then -- A is most likely a number
			local t = {}
			t.time = b.time - a
			setmetatable(t, meta)
			return t
		elseif not getmetatable(b) then -- B is most likely a number
			local t = {}
			t.time = a.time - b
			setmetatable(t, meta)
			return t
		else -- Both is a form of an object
			if a.unix and b.time then
				return NikNaks.DateTime(a.unix - b.time)
			elseif b.unix and a.time then
				return NikNaks.DateTime(b.unix - a.time)
			else
				local t = {}
				t.time = (a.time or a) - (b.time or b)
				setmetatable(t, meta)
				return t
			end
		end
	end

	function meta.__mul(a, b)
		if not getmetatable(a) then -- A is most likely a number
			local t = {}
			t.time = b.time * a
			setmetatable(t, meta)
			return t
		elseif not getmetatable(b) then -- B is most likely a number
			local t = {}
			t.time = a.time * b
			setmetatable(t, meta)
			return t
		else -- Both is a form of an object
			local t = {}
			t.time = (a.time or a) * (b.time or b)
			setmetatable(t, meta)
			return t
		end
	end

	function meta.__div(a, b)
		if not getmetatable(a) then -- A is most likely a number
			local t = {}
			t.time = b.time / a
			setmetatable(t, meta)
			return t
		elseif not getmetatable(b) then -- B is most likely a number
			local t = {}
			t.time = a.time / b
			setmetatable(t, meta)
			return t
		else -- Both is a form of an object
			local t = {}
			t.time = (a.time or a) / (b.time or b)
			setmetatable(t, meta)
			return t
		end
	end

	function meta.__pow(a, b)
		if not getmetatable(a) then -- A is most likely a number
			local t = {}
			t.time = b.time ^ a
			setmetatable(t, meta)
			return t
		elseif not getmetatable(b) then -- B is most likely a number
			local t = {}
			t.time = a.time ^ b
			setmetatable(t, meta)
			return t
		else -- Both is a form of an object
			local t = {}
			t.time = (a.time or a) ^ (b.time or b)
			setmetatable(t, meta)
			return t
		end
	end

	function meta.__mod(a, b)
		if not getmetatable(a) then -- A is most likely a number
			local t = {}
			t.time = b.time % a
			setmetatable(t, meta)
			return t
		elseif not getmetatable(b) then -- B is most likely a number
			local t = {}
			t.time = a.time % b
			setmetatable(t, meta)
			return t
		else -- Both is a form of an object
			local t = {}
			t.time = (a.time or a) % (b.time or b)
			setmetatable(t, meta)
			return t
		end
	end

	function meta.__concat(a, b)
		return tostring(a) .. tostring(b)
	end

	-- Sadly Lua doesn't support mixed types for compare-operations
	function meta.__eq(a, b)
		return a.time == b.time
	end
	
	function meta.__lt(a, b)
		return a.time < b.time
	end
	
	function meta.__le(a, b)
		return a.time <= b.time
	end
end
