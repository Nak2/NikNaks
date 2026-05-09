-- Copyright © 2022-2072, Nak, https://steamcommunity.com/id/Nak2/
-- All Rights Reserved. Not allowed to be reuploaded.
-- License: https://github.com/Nak2/NikNaks/blob/main/LICENSE

local s_char, s_byte, tostring = string.char, string.byte, tostring
local band, brshift, blshift, bor, bswap = bit.band, bit.rshift, bit.lshift, bit.bor, bit.bswap
local log, ldexp, frexp, floor, ceil, max, setmetatable, source = math.log, math.ldexp, math.frexp, math.floor, math
	.ceil, math.max, setmetatable, jit.util.funcinfo(NikNaks.AutoInclude)["source"]

--- Creates a new BitBuffer. 
---@overload fun(data: string|table?, little_endian: boolean?) : BitBuffer
NikNaks.BitBuffer = {}

---@class BitBuffer
---@field private _data number[]
---@field private _tell number
---@field private _len number
---@field private _little_endian boolean
local meta = {}
meta.__index = meta
function meta:__tostring()
	return "BitBuffer [" .. self:Size() .. "]"
end

---@diagnostic disable: invisible

--- Fixes bit-shift errors
---@param int number
---@param shift number
---@return number
local function rshift(int, shift)
	if shift > 31 then return 0x0 end
	return brshift(int, shift)
end

---@param int number
---@param shift number
---@return number
local function lshift(int, shift)
	if shift > 31 then return 0x0 end
	return blshift(int, shift)
end

-- "Crams" the data into the bitbuffer. Ignoring offsets
local function unsaferawdata(self, str)
	if #str <= 0 then return end

	local len = #str
	local p = #self._data
	local whole = lshift(rshift(len - 4, 2), 2) -- Bytes

	for i = 1, whole, 4 do
		local a, b, c, d = s_byte(str, i, i + 3)
		p = p + 1
		self._data[p] = bor(lshift(a, 24), lshift(b, 16), lshift(c, 8), d)
	end

	self._tell = lshift(p, 5)
	for i = whole + 1, len do
		meta.WriteByte(self, s_byte(str, i))
	end

	self._len = max(self._len, lshift(len, 3))
end

--- Creates a new BitBuffer.
---@param data? string|table # Data
---@param little_endian? boolean # Defaults to true
---@return BitBuffer
local function create(data, little_endian)
	---@type BitBuffer
	local t = {
		_data = {},
		_tell = 0,
		_len = 0,
		_little_endian = little_endian == nil and true or little_endian or false
	}
	setmetatable(t, meta)

	if not data then return t end
	local mt = getmetatable(data)

	if type(data) == "string" then
		unsaferawdata(t, data)
		t._tell = 0 -- Reset tell
	elseif not mt then
		local q = #data
		for i = 1, q do
			t._data[i] = data[i]
		end
		t._len = q * 32
	end

	return t
end

NikNaks.BitBuffer.Create = create
setmetatable(NikNaks.BitBuffer, {
	__call = function(_, data, little_endian) return create(data, little_endian) end
})

-- Simple int->string and reverse. ( Little-Endian )
do
	--- Takes a string of 1-4 characters and converts it into a Little-Endian integer.
	---@param str string
	---@return number
	function NikNaks.BitBuffer.StringToInt(str)
		local a, b, c, d = s_byte(str, 1, 4)
		if d then
			return bor(blshift(d, 24), blshift(c, 16), blshift(b, 8), a)
		elseif c then
			return bor(blshift(c, 16), blshift(b, 8), a)
		elseif b then
			return bor(blshift(b, 8), a)
		else
			return a
		end
	end

	local q = 0xFF
	--- Takes a Little-Endian integer and converts it into a 4-character string.
	---@param int number
	---@return string
	function NikNaks.BitBuffer.IntToString(int)
		local a, b, c, d = brshift(int, 24), band(brshift(int, 16), q), band(brshift(int, 8), q), band(int, q)
		return s_char(d, c, b, a)
	end
end

-- To signed and unsigned
local to_signed
do
	local maxint = {}
	for i = 1, 32 do
		local n = i
		maxint[i] = math.pow(2, n - 1)
	end

	function to_signed(int, bits)
		if int < 0 then return int end -- Already signed
		local maximum = maxint[bits]
		return int - band(int, maximum) * 2
	end
end

-- Access
do
	--- Returns the total size of the BitBuffer in bits.
	---@return number
	function meta:__len()
		return self._len
	end

	meta.Size = meta.__len

	--- Returns the current read/write cursor position in bits.
	---@return number
	function meta:Tell()
		return self._tell
	end

	--- Sets the read/write cursor to an absolute bit position.
	---@param num number
	---@return self
	function meta:Seek(num)
		self._tell = bit.bor(num, 0)
		return self
	end

	--- Advances the cursor forward by the given number of bits.
	---@param num number
	---@return BitBuffer self
	function meta:Skip(num)
		self._tell = self._tell + num
		return self
	end

	--- Returns true if the cursor has reached or passed the end of the data.
	---@return boolean
	function meta:EndOfData()
		return self._tell >= self._len
	end

	--- Clears all data from the BitBuffer.
	---@return BitBuffer self
	function meta:Clear()
		self._data = {}
		self._len = 0
		self._tell = 0
		return self
	end

	--- Converts a number to bits. ( Big-Endian )
	---@param num number
	---@param bits number
	---@return string
	local function toBits(num, bits, byte_space)
		local str = ""
		for i = bits, 1, -1 do
			if byte_space and i % 8 == 0 and i < 32 then
				str = str .. " "
			end
			local b = band(num, lshift(0x1, i - 1)) == 0
			str = str .. (b and "0" or "1")
		end
		return str
	end
	NikNaks.BitBuffer.ToBits = toBits

	--- Debug print function for the bitbuffer.
	function meta:Debug(maxRows)
		maxRows = maxRows or 10
		local size = string.NiceSize(self._len / 8)
		local rep = string.rep("=", (32 - (#size + 6)) / 2)
		print("BitBuff  " ..
			rep .. " [" .. size .. "] " .. (self:IsLittleEndian() and "Le " or "Be ") .. rep .. "\t= 0xHX =\t= CHAR =")

		local lines = math.ceil(self._len / 32)
		local foundData = nil

		for i = 1, lines do
			if not foundData then
				if not self._data[i] then continue end
				foundData = i
			elseif i > foundData + maxRows then
				break
			end

			local bits, hex, chars

			if not self._data[i] then
				bits  = "00000000000000000000000000000000"
				hex   = "00000000"
				chars = "...."
			else
				local word = self._data[i]
				bits = toBits(word, 32)
				hex  = bit.tohex(word):upper()

				local b1 = bit.rshift(bit.band(word, 0xFF000000), 24)
				local b2 = bit.rshift(bit.band(word, 0x00FF0000), 16)
				local b3 = bit.rshift(bit.band(word, 0x0000FF00),  8)
				local b4 =             bit.band(word, 0x000000FF)

				local function toChar(b)
					return (b >= 32 and b <= 126) and string.char(b) or "."
				end

				chars = toChar(b1) .. toChar(b2) .. toChar(b3) .. toChar(b4)
			end

			print(i * 4 - 4, bits, hex, "  " .. chars)
		end
	end

	--- Returns true if the bitbuffer is little-endian.
	---@return boolean
	function meta:IsLittleEndian()
		return self._little_endian or false
	end

	--- Returns true if the bitbuffer is big-endian.
	---@return boolean
	function meta:IsBigEndian()
		return not self._little_endian
	end

	--- Sets the bitbuffer to be little-endian.
	---@return self BitBuffer The BitBuffer that was modified
	function meta:SetLittleEndian()
		self._little_endian = true
		return self
	end

	--- Sets the bitbuffer to be big-endian.
	---@return self BitBuffer The BitBuffer that was modified
	function meta:SetBigEndian()
		self._little_endian = false
		return self
	end
end

-- Write / Read Raw
local writeraw, readraw
do
	-- Need to check endian type here.
	-- B |--|--|FF|11|
	-- L |--|--|11|FF|

	-- B |--|-F|FF|11| -- Input
	-- S |11|FF|-F|--| -- Swap
	-- > |--|11|FF|-F| -- rshift
	-- L |--|-1|1F|FF| -- Output

	-- B |00000000|00000000|00000000|00000000|
	local b_mask = 0xFFFFFFFF

	---@param int number
	---@param bits number
	---@return number
	local function swap(int, bits)
		return brshift(bswap(int), 32 - bits)
	end

	---@param self BitBuffer
	---@param int number
	---@param bits number
	---@return self BitBuffer The BitBuffer that was modified
	function writeraw(self, int, bits)
		if self._little_endian and bits % 8 == 0 then
			int = swap(int, bits)
		end

		local tell = self._tell
		self._tell = tell + bits
		self._len = max(self._len, self._tell)

		-- Retrive data pos
		local i_word = rshift(tell, 5) + 1 -- [ 1 - length ]
		local bitPos = tell % 32     -- [[ 0 - 31 ]]
		local ebitPos = bitPos + bits -- The end bit pos

		-- DataMask & Data
		local mask = bor(lshift(b_mask, 32 - bitPos), rshift(b_mask, ebitPos))
		local data = band(self._data[i_word] or 0x0, mask)

		-- Write the data
		if ebitPos <= 32 then
			self._data[i_word] = bor(data, lshift(int, 32 - ebitPos))
			return self
		end

		local overflow = ebitPos - 32 -- [[ 1, 31 ]]
		self._data[i_word] = bor(data, rshift(int, overflow))

		data = band(rshift(b_mask, overflow), self._data[i_word + 1] or 0x0)
		self._data[i_word + 1] = bor(data, lshift(int, 32 - overflow))

		return self
	end

	---@param self BitBuffer
	---@param bits number
	---@return number # The read data
	function readraw(self, bits)
		local tell = self._tell
		self._tell = tell + bits

		-- Retrive data pos
		local i_word = rshift(tell, 5) + 1 -- [ 1 - length ]
		local bitPos = tell % 32     -- [[ 0 - 31 ]]
		local ebitPos = bitPos + bits -- The end bit pos

		-- DataMask & Data
		if ebitPos <= 32 then
			local data = brshift(self._data[i_word] or 0x0, 32 - ebitPos)
			if self._little_endian and bits % 8 == 0 then
				return swap(band(data, brshift(b_mask, 32 - bits)), bits)
			end
			return band(data, brshift(b_mask, 32 - bits))
		end

		local over = ebitPos - 32 -- How many bits we're over
		local data1 = lshift(band(self._data[i_word] or 0x0, rshift(b_mask, bitPos)), over)
		local data2 = rshift(self._data[i_word + 1] or 0x0, 32 - over)
		if self._little_endian and bits % 8 == 0 then
			return swap(bor(data1, data2), bits)
		end

		return bor(data1, data2)
	end

	if not source:find("niknak") then return end
end

--- Add raw (debug) functions
meta._writeraw = writeraw
meta._readraw = readraw

-- Boolean
do
	local b_mask = 0xFFFFFFFF
	--We don't need to call write/read raw. Since this is 1 bit.

	--- Writes a boolean.
	---@param b boolean
	---@return self BitBuffer
	function meta:WriteBoolean(b)
		local tell = self._tell
		self._tell = tell + 1
		self._len = max(self._len, self._tell)

		-- Retrive data pos
		local i_word = rshift(tell, 5) + 1 -- [ 1 - length ]
		local bitPos = tell % 32     -- [[ 0 - 31 ]]
		local ebitPos = bitPos + 1

		-- DataMask & Data
		local mask = bor(lshift(b_mask, 32 - bitPos), rshift(b_mask, ebitPos))
		local data = band(self._data[i_word] or 0x0, mask)

		-- Write the data
		self._data[i_word] = bor(data, lshift(b and 1 or 0, 32 - ebitPos))

		return self
	end

	--- Reads a boolean.
	---@return boolean
	function meta:ReadBoolean()
		local tell = self._tell
		self._tell = tell + 1

		-- Retrive data pos
		local i_word = rshift(tell, 5) + 1 -- [ 1 - length ]
		local bitPos = tell % 32     -- [[ 0 - 31 ]]
		local ebitPos = bitPos + 1   -- The end bit pos

		-- DataMask & Data
		local data = rshift(self._data[i_word] or 0x0, 32 - ebitPos)

		return band(data, rshift(b_mask, 32 - 1)) == 1
	end
end

-- 32 bit Int
do
	meta.WriteInt = writeraw

	--- Reads an int.
	---@param bits number
	---@return number
	function meta:ReadInt(bits)
		return to_signed(readraw(self, bits), bits)
	end
end

-- UInt
do
	meta.WriteUInt = writeraw

	local c = math.pow(2, 32)

	--- Reads an unsigned int.
	---@param bits number
	---@return number
	function meta:ReadUInt(bits)
		local n = readraw(self, bits)
		if n > -1 then return n end -- 32bit numbers could be negative when reading.
		return n + c
	end
end

-- Byte
do
	--- Writes a byte. ( 0 - 255 )
	---@param byte number
	---@return BitBuffer self
	function meta:WriteByte(byte)
		writeraw(self, byte, 8)
		return self
	end

	--- Reads a byte. ( 0 - 255 )
	---@return number
	function meta:ReadByte()
		return readraw(self, 8)
	end
end

-- Signed Byte
do
	--- Writes a signed byte. ( -128 - 127 )
	---@param byte number
	---@return BitBuffer self
	function meta:WriteSignedByte(byte)
		self:WriteInt(byte, 8)
		return self
	end

	--- Reads a signed byte. ( -128 - 127 )
	---@return number
	function meta:ReadSignedByte()
		return self:ReadInt(8)
	end
end

-- Ushort
do
	--- Writes an unsigned 2 byte number. ( 0 - 65535 )
	---@param num number
	---@return BitBuffer self
	function meta:WriteUShort(num)
		self:WriteUInt(num, 16)
		return self
	end

	--- Reads an unsigned 2 byte number. ( 0 - 65535 )
	---@return number
	function meta:ReadUShort()
		return self:ReadUInt(16)
	end
end

-- Short
do
	--- Writes a 2 byte number. ( -32768 - 32767 )
	---@param num number
	---@return BitBuffer self
	function meta:WriteShort(num)
		self:WriteInt(num, 16)
		return self
	end

	--- Reads a 2-byte signed number. ( -32768 - 32767 )
	---@return number
	function meta:ReadShort()
		return self:ReadInt(16)
	end
end

-- ULong
do
	--- Writes an unsigned 4 byte number. ( 0 - 4294967295 )
	---@param num number
	---@return self BitBuffer
	function meta:WriteULong(num)
		self:WriteUInt(num, 32)
		return self
	end

	--- Reads an unsigned 4 byte number ( 0 - 4294967295 )
	---@return number
	function meta:ReadULong()
		return self:ReadUInt(32)
	end
end

-- Long
do
	--- Writes a 4 byte number. ( -2147483648 - 2147483647 )
	---@param num number
	---@return BitBuffer self
	function meta:WriteLong(num)
		self:WriteInt(num, 32)
		return self
	end

	--- Reads a 4 byte number. ( -2147483648 - 2147483647 )
	---@return number
	function meta:ReadLong()
		return self:ReadInt(32)
	end
end

-- Nibble
do
	--- Writes a 4 bit unsigned number. ( 0 - 15 )
	---@param num number
	---@return BitBuffer self
	function meta:WriteNibble(num)
		self:WriteUInt(num, 4)
		return self
	end

	--- Reads a 4 bit unsigned number. ( 0 - 15 )
	---@return number
	function meta:ReadNibble()
		return self:ReadUInt(4)
	end
end

-- Snort ( 2bit number )
do
	--- Writes a 2 bit unsigned number. ( 0 - 3 )
	---@param num number
	---@return BitBuffer self
	function meta:WriteSnort(num)
		self:WriteUInt(num, 2)
		return self
	end

	--- Reads a 2 bit unsigned number. ( 0 - 3 )
	---@return number
	function meta:ReadSnort()
		return self:ReadUInt(2)
	end
end

---@param n number
---@return boolean
local function isNegative(n) return 1 / n == -math.huge end

-- Float
do
	--- Writes an IEEE 754 little-endian float.
	---@param num number
	---@return self BitBuffer
	function meta:WriteFloat(num)
		local sign = 0
		local man = 0
		local ex = 0

		-- Mark negative numbers.
		if num < 0 then
			sign = 0x80000000
			num = -num
		end

		if num ~= num then -- Nan
			ex = 0xFF
			man = 1
		elseif num == math.huge then -- Infintiy
			ex = 0xFF
			man = 0
		elseif num ~= 0 then -- Anything but 0's
			man, ex = frexp(num)
			ex = ex + 0x7F

			if ex <= 0 then
				man = ldexp(man, ex - 1)
				ex = 0
			elseif ex >= 0xFF then -- Reached infinity
				ex = 0xFF
				man = 0
			elseif ex == 1 then
				ex = 0
			else
				man = man * 2 - 1
				ex = ex - 1
			end

			man = floor(ldexp(man, 23) + 0.5)
		elseif isNegative(num) then -- Minus 0 support
			sign = 0x80000000
			man = 0
		end

		-- Not tested, but I guess it is faster to write 1 32bit number, than 3x others.
		self:WriteULong(bor(sign, lshift(band(ex, 0xFF), 23), man))

		return self
	end

	local _23pow = 2 ^ 23

	--- Reads an IEEE 754 little-endian float.
	---@return number
	function meta:ReadFloat()
		local n = self:ReadULong()
		local sign = band(0x80000000, n) == 0 and 1 or -1
		local ex = band(rshift(n, 23), 0xFF)
		local man = band(n, 0x007FFFFF) / _23pow

		if ex == 0 and man == 0 then
			return 0 * sign -- Number 0
		elseif ex == 255 and man == 0 then
			return math.huge * sign -- -+inf
		elseif ex == 255 and man ~= 0 then
			return 0 / 0   -- nan
		else
			return ldexp(1 + man, ex - 127) * sign
		end
	end
end

-- Double
do
	--[[
		|FFFFFFFF|FFFFFFFF|
		|Fa|Fb|Fc|Fd| |Fe|Ff|Fg|Fh|
		|Fh|Fg|Ff|Fe| |Fd|Fc|Fb|Fa| -> Data input

		|Fh|Fg|Ff|Fe| |Fd|Fc|Fb|Fa|
		|Fe|Ff|Fg|Fh| |Fa|Fb|Fc|Fd|
		|Fa|Fb|Fc|Fd| |Fe|Ff|Fg|Fh|
	]]
	local _1022pow = 2^-1022
	local _52pow = 2 ^ -52
	local _32pow = 2 ^ 32
	local _20pow = 2^-20

	--- Writes an IEEE 754 little-endian double.
	---@param num number
	---@return BitBuffer self
	function meta:WriteDouble(num)
		-- Handle special cases first
		local sign = 0
		if num < 0 or (num == 0 and isNegative(num)) then
			num = -num
			sign = 0x80000000
		end

		local ex, man_hi, man_lo
		if num == 0 then -- Zero
			ex, man_hi, man_lo = 0, 0, 0
		elseif num ~= num then -- NaN
			ex, man_hi, man_lo = 2047, 0, 1
		elseif num == math.huge then -- Infinity
			ex, man_hi, man_lo = 2047, 0, 0
		else
    	local m, e = math.frexp(num)
		ex = e + 1022
		if ex >= 2047 then
			ex, man_hi, man_lo = 2047, 0, 0
		elseif ex <= 0 then
			local shift = 1 - ex  -- how many bits to shift mantissa right
			m = m * 2^(20 - shift)  -- scale to 20-bit hi field with shift applied
			man_hi = math.floor(m)
			man_lo = math.floor((m - man_hi) * _32pow + 0.5)
			ex = 0
		else
			m = m * 2 - 1
			local man_hi_f = math.floor(m * 2^20)
			local m_frac = m * 2^20 - man_hi_f
			man_hi = man_hi_f
			man_lo = math.floor(m_frac * _32pow + 0.5)
		end
	end

		if self._little_endian then
			self:WriteULong(man_lo)
			self:WriteULong(bor(sign, lshift(ex, 20), band(man_hi, 0x000FFFFF)))
		else
			self:WriteULong(bor(sign, lshift(ex, 20), band(man_hi, 0x000FFFFF)))
			self:WriteULong(man_lo)
		end

		return self
	end

	--- Reads an IEEE 754 little- or big-endian double.
	---@return number
	function meta:ReadDouble()
		local a, b
		if self._little_endian then
			b, a = self:ReadULong(), self:ReadULong()
		else
			a, b = self:ReadULong(), self:ReadULong()
		end

		local sign = band(0x80000000, a) == 0 and 1 or -1
		local ex = rshift(band(0x7FF00000, a), 20)
		local man_hi = band(a, 0x000FFFFF)
		local man_lo = band(b, 0xFFFFFFFF)

		if ex == 0 and man_hi == 0 and man_lo == 0 then
			return 0 * sign -- ± Zero
		elseif ex == 0x7FF and man_hi == 0 and man_lo == 0 then
			return math.huge * sign -- Infinity
		elseif ex == 0x7FF then
			return 0 / 0   -- NaN
		elseif ex == 0 then
			-- Subnormal: sign * (0.mantissa) * 2^-1022
			return sign * (man_hi * _20pow + man_lo * _52pow) * _1022pow
		else
			-- Normal: sign * (1.mantissa) * 2^(ex-1023)
			return sign * (1 + man_hi * _20pow + man_lo * _52pow) * 2^(ex - 1023)
		end
	end
end

-- Data
do
	--- Writes raw string-data.
	---@param str string
	---@return BitBuffer self
	function meta:Write(str)
		local len = #str
		local q = lshift(rshift(len, 2), 2)

		for i = 1, q, 4 do
			local a, b, c, d = s_byte(str, i, i + 3)
			self:WriteUInt(bor(lshift(a, 24), lshift(b, 16), lshift(c, 8), d), 32)
		end

		for i = q + 1, len do
			self:WriteUInt(s_byte(str, i), 8)
		end

		return self
	end

	--- Reads raw string-data. Default bytes are the length of the bitbuffer.
	---@param bytes number? If not given, will read until the end of the bitbuffer.
	---@return string
	function meta:Read(bytes)
		bytes = bytes or math.ceil((self:Size() - self:Tell()) / 8)

		local ReadByte = meta.ReadByte
		local c, s = lshift(rshift(bytes, 2), 2), ""

		for _ = 1, c, 4 do
			s = s .. s_char(ReadByte(self), ReadByte(self), ReadByte(self), ReadByte(self))
		end

		for _ = c + 1, bytes do
			s = s .. s_char(ReadByte(self))
		end

		return s
	end

	--- Writes raw bytes directly, ignoring the endianness setting.
	---@param str string
	---@return BitBuffer
	function meta:WriteData(str)
		local len = #str
		local q = lshift(rshift(len, 2), 2)

		for i = 1, q, 4 do
			local a, b, c, d = s_byte(str, i, i + 3)
			self:WriteByte(a)
			self:WriteByte(b)
			self:WriteByte(c)
			self:WriteByte(d)
		end

		for i = q + 1, len do
			self:WriteByte(s_byte(str, i))
		end

		return self
	end

	--- Reads raw bytes directly, ignoring the endianness setting.
	---@param bytes number
	---@return string
	function meta:ReadData(bytes)
		local ReadByte = meta.ReadByte
		local c, s = lshift(rshift(bytes, 2), 2), ""

		for _ = 1, c, 4 do
			s = s .. s_char(ReadByte(self), ReadByte(self), ReadByte(self), ReadByte(self))
		end

		for _ = c + 1, bytes do
			s = s .. s_char(ReadByte(self))
		end

		return s
	end

end

-- Special Types
do
	local Write, Read = meta.Write, meta.Read

	--- Writes a string. Max string length: 65535
	---@param str string
	---@return BitBuffer self
	function meta:WriteString(str)
		local l = #str
		if l > 65535 then
			str = str:sub(0, 65535)
			l = 65535
		end

		self:WriteUShort(l)
		self:WriteData(str)

		return self
	end

	--- Reads a string. Max string length: 65535
	---@return string
	function meta:ReadString()
		return self:ReadData(self:ReadUShort() or 0)
	end

	local z = '\0'

	--- Writes a null-terminated string. Any embedded null bytes in the input are stripped.
	---@param str string
	---@return BitBuffer self
	function meta:WriteStringNull(str)
		self:WriteData(string.gsub(str, z, '') .. z)
		return self
	end

	--- Reads a null-terminated string. Slightly slower than ReadString due to byte-by-byte scanning.
	---@param maxLength? number
	---@return string
	function meta:ReadStringNull(maxLength)
		maxLength = maxLength or ceil((self:Size() - self:Tell()) / 8)

		local str = ""
		if maxLength < 1 then return str end

		local c = self:ReadByte()
		while c ~= 0 and maxLength > 0 do
			str = str .. s_char(c)
			c = self:ReadByte()
			maxLength = maxLength - 1
		end

		return str
	end

	--- Writes a Vector.
	---@param vector Vector
	---@return BitBuffer self
	function meta:WriteVector(vector)
		self:WriteFloat(vector.x)
		self:WriteFloat(vector.y)
		self:WriteFloat(vector.z)
		return self
	end

	--- Reads a Vector.
	---@return Vector
	function meta:ReadVector()
		return Vector(self:ReadFloat(), self:ReadFloat(), self:ReadFloat())
	end

	--- Writes an Angle.
	---@param angle Angle
	---@return BitBuffer self
	function meta:WriteAngle(angle)
		self:WriteFloat(angle.p)
		self:WriteFloat(angle.y)
		self:WriteFloat(angle.r)
		return self
	end

	--- Reads an Angle.
	---@return Angle
	function meta:ReadAngle()
		return Angle(self:ReadFloat(), self:ReadFloat(), self:ReadFloat())
	end

	--- Writes a 32bit Color.
	---@param color Color
	---@return self BitBuffer
	function meta:WriteColor(color)
		self:WriteByte(color.r)
		self:WriteByte(color.g)
		self:WriteByte(color.b)
		self:WriteByte(color.a or 255)
		return self
	end

	--- Reads a 32bit color.
	---@return Color
	function meta:ReadColor()
		return Color(self:ReadByte(), self:ReadByte(), self:ReadByte(), self:ReadByte())
	end
end

-- Tables / Types
do
	local typeIDs = {
		["nil"]     = 0,
		["boolean"] = 1,
		["number"]  = 2,
		-- light userdata
		["string"]  = 4,
		["table"]   = 5,
		-- function
		-- userdata
		-- thread
		["Entity"]  = 9,
		["Vector"]  = 10,
		["Angle"]   = 11,
		-- physobj
		["Color"]   = 255
	}

	--- Writes a type using a byte as TYPE_ID.
	---@param obj any
	---@return BitBuffer self
	function meta:WriteType(obj)
		local id = TypeID(obj)

		if id == TYPE_TABLE and obj.r and obj.g and obj.b then
			id = TYPE_COLOR
		end

		self:WriteByte(id)
		if id == TYPE_NIL then return self end

		if id == TYPE_BOOL then
			self:WriteByte(obj and 1 or 0)
		elseif id == TYPE_NUMBER then
			self:WriteDouble(obj)
		elseif id == TYPE_STRING then
			self:WriteString(obj)
		elseif id == TYPE_TABLE then
			self:WriteTable(obj)
		elseif id == TYPE_ENTITY then
			self:WriteULong(obj:EntIndex())
		elseif id == TYPE_VECTOR then
			self:WriteVector(obj)
		elseif id == TYPE_ANGLE then
			self:WriteAngle(obj)
		elseif id == TYPE_COLOR then
			self:WriteColor(obj)
		end

		return self
	end

	--- Reads a type using a byte as TYPE_ID.
	---@return any
	function meta:ReadType()
		local id = self:ReadByte()

		if id == TYPE_NIL then
			return
		elseif id == TYPE_BOOL then
			return self:ReadByte() == 1
		elseif id == TYPE_NUMBER then
			return self:ReadDouble()
		elseif id == TYPE_STRING then
			return self:ReadString()
		elseif id == TYPE_TABLE then
			return self:ReadTable()
		elseif id == TYPE_ENTITY then
			return Entity(self:ReadULong())
		elseif id == TYPE_VECTOR then
			return self:ReadVector()
		elseif id == TYPE_ANGLE then
			return self:ReadAngle()
		elseif id == TYPE_COLOR then
			return self:ReadColor()
		end
	end

	--- Writes a table
	---@param tab table
	---@return self BitBuffer
	function meta:WriteTable(tab)
		for k, v in pairs(tab) do
			self:WriteType(k)
			self:WriteType(v)
		end

		self:WriteByte(0)

		return self
	end

	--- Reads a table. Default maxValues is 150
	---@param maxValues? number
	---@return table
	function meta:ReadTable(maxValues)
		maxValues = maxValues or 150

		-- Table
		local tab = {}
		local k = self:ReadType()

		while k ~= nil and maxValues > 0 do
			tab[k] = self:ReadType()
			k = self:ReadType()
			maxValues = maxValues - 1
		end

		return tab
	end
end

-- File functions
do
	--- Same as file.Open, but returns it as a bitbuffer. little_endian is true by default.
	---@param fileName string
	---@param gamePath? string
	---@param lzma? boolean
	---@param little_endian? boolean
	---@return BitBuffer?
	function NikNaks.BitBuffer.OpenFile(fileName, gamePath, lzma, little_endian)
		if gamePath == true then gamePath = "GAME" end
		if gamePath == nil then gamePath = "DATA" end
		if gamePath == false then gamePath = "DATA" end

		local f = file.Open(fileName, "rb", gamePath)
		if not f then return nil end

		-- Data
		local str = f:Read(f:Size()) -- Is faster
		if lzma then
			str = util.Decompress(str) or str
		end

		f:Close()

		---@type BitBuffer
		local b = NikNaks.BitBuffer(str, little_endian)
		b:Seek(0)

		return b
	end

	--- Saves the bitbuffer to a file within the data folder. Returns true if it got saved.
	---@param fileName string
	---@param lzma? boolean
	---@return boolean
	function meta:SaveToFile(fileName, lzma)
		local f = file.Open(fileName, "wb", "DATA")
		if not f then return false end

		local s = self:Size()
		local t = self:Tell()

		if lzma then
			self:Seek(0)
			local data = self:Read()
			data = util.Compress(data) or data
			f:Write(data)
		else
			self:Seek(0)

			local b_pos = math.floor(s / 32)
			for i = 1, b_pos do
				f:WriteULong(bswap(self._data[i]))
			end

			local bytesLeft = (s % 32) / 8
			if bytesLeft > 0 then
				self:Seek(b_pos * 32)

				for i = 1, bytesLeft do
					local b = self:ReadByte()
					f:WriteByte(b)
				end
			end
		end

		self:Seek(t)
		f:Close()

		return true
	end
end

-- Net functions

--- Reads a bitbuffer from the net and returns self.
---@param bits number
---@return self
function meta:ReadFromNet(bits)
	for i = 1, bits / 32 do
		self:WriteUInt(net.ReadUInt(32), 32)
	end

	local leftover = bits % 32
	if leftover > 0 then
		self:WriteUInt(net.ReadUInt(leftover), leftover)
	end

	self:Seek(0)
	return self
end

--- Creates and reads a bitbuffer from the net and returns it.
---@param bits number
---@return BitBuffer
function NikNaks.BitBuffer.FromNet(bits)
	return NikNaks.BitBuffer():ReadFromNet(bits)
end

--- Writes the bitbuffer to the net and returns the size.
---@return number # The size of the bitbuffer
function meta:WriteToNet()
	local tell = self:Tell()
	self:Seek(0)

	local l = self:Size()
	for _ = 1, l / 32 do
		net.WriteUInt(self:ReadULong(), 32)
	end

	local leftover = l % 32
	if leftover > 0 then
		net.WriteUInt(self:ReadUInt(leftover), leftover)
	end

	self:Seek(tell)
	return l
end

--- Writes the bitbuffer to the net and returns the size.
---@param buf BitBuffer
---@return number # The size of the bitbuffer
function NikNaks.BitBuffer.ToNet(buf)
	return buf:WriteToNet()
end

---@diagnostic enable: invisible