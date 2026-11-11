-- Copyright © 2022-2072, Nak, https://steamcommunity.com/id/Nak2/
-- All Rights Reserved. Not allowed to be reuploaded.
-- License: https://github.com/Nak2/NikNaks/blob/main/LICENSE

local s_char, s_byte, tostring = string.char, string.byte, tostring
local band, brshift, blshift, bor, bswap, bnot = bit.band, bit.rshift, bit.lshift, bit.bor, bit.bswap, bit.bnot
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
	return ( brshift(int, shift) )
end

---@param int number
---@param shift number
---@return number
local function lshift(int, shift)
	if shift > 31 then return 0x0 end
	return ( blshift(int, shift) )
end

-- "Crams" the data into the bitbuffer. Ignoring offsets
local function unsaferawdata(self, str)
	if #str <= 0 then return end

	local len = #str
	local p = #self._data
	local whole = len >= 4 and lshift(rshift(len - 4, 2), 2) or 0

	for i = 1, whole, 4 do
		local a, b, c, d = s_byte(str, i, i + 3)
		p = p + 1
		self._data[p] = bor(blshift(a, 24), blshift(b, 16), blshift(c, 8), d)
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
setmetatable(NikNaks.BitBuffer --[[@as table]], {
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
			return ( bor(blshift(d, 24), blshift(c, 16), blshift(b, 8), a) )
		elseif c then
			return ( bor(blshift(c, 16), blshift(b, 8), a) )
		elseif b then
			return ( bor(blshift(b, 8), a) )
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
		return ( s_char(d, c, b, a) )
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
		self._tell = bor(num, 0)
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

	local function toChar(b)
		return (b >= 32 and b <= 126) and string.char(b) or "."
	end

	--- Debug print function for the bitbuffer.
	---@param maxRows number? Maximum number of rows to display. Default is 10.
	function meta:Debug(maxRows)
		maxRows = maxRows or 10

		local size = string.NiceSize(self._len / 8)
		local startTell = self:Tell()
		local bitOffset = startTell % 8

		-- Alignment info
		local alignStr = bitOffset == 0 and "aligned" or ("misaligned +" .. bitOffset .. "b")

		-- Header
		local label = " [" .. size .. "] " .. (self:IsLittleEndian() and "LE" or "BE") .. " | " .. alignStr .. " "
		local totalWidth = 72
		local padTotal = totalWidth - #label
		local padL = math.floor(padTotal / 2)
		local padR = padTotal - padL
		print(string.rep("=", padL) .. label .. string.rep("=", padR))
		print(string.format("  %-14s  %-35s  %-11s  %s", "byte", "bits (4 bytes)", "hex", "char"))
		print(string.rep("-", 72))

		local function fmtBytePos(bitPos)
			local byte = math.floor(bitPos / 8)
			if bitOffset == 0 then
				return ( string.format("%d", byte) )
			else
				return ( string.format("%d+%db", byte, bitOffset) )
			end
		end

		for i = 1, maxRows do
			local bytesLeft = math.ceil((self._len - self._tell) / 8)
			if bytesLeft <= 0 then break end

			local b = {}
			local valid = {}
			for j = 1, 4 do
				valid[j] = bytesLeft >= j
				b[j] = valid[j] and self:ReadByte() or 0
			end

			local bitsStr = ""
			for j = 1, 4 do
				bitsStr = bitsStr .. (valid[j] and toBits(b[j], 8) or "........") .. " "
			end

			local hexStr = ""
			for j = 1, 4 do
				hexStr = hexStr .. (valid[j] and string.format("%02X ", b[j]) or ".. ")
			end

			local charStr = ""
			for j = 1, 4 do
				charStr = charStr .. (valid[j] and toChar(b[j]) or ".")
			end

			local rowBitPos = startTell + (i - 1) * 32
			local rowMarker = i == 1 and ">" or " "

			print(string.format("%s %-14s  %-35s  %-11s  %s",
				rowMarker, fmtBytePos(rowBitPos), bitsStr, hexStr, charStr))
		end

		print(string.rep("=", 72))
		self:Seek(startTell)
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
local writeraw, readraw, writeraw32, readraw32
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

	---@param self BitBuffer
	---@param int number
	---@param bits number
	---@return self BitBuffer The BitBuffer that was modified
	function writeraw(self, int, bits)
		if self._little_endian and band(bits, 7) == 0 then
			int = brshift(bswap(int), 32 - bits)
		elseif bits < 32 then
			-- Only the low `bits` bits are the value.
			int = band(int, brshift(b_mask, 32 - bits))
		end

		local tell = self._tell
		local newTell = tell + bits
		self._tell = newTell
		if newTell > self._len then self._len = newTell end

		-- Retrive data pos
		local data = self._data
		local i_word = brshift(tell, 5) + 1 -- [ 1 - length ]
		local bitPos = band(tell, 31) -- [[ 0 - 31 ]]
		local ebitPos = bitPos + bits -- The end bit pos

		if ebitPos <= 32 then
			-- Fits in one word: clear the `bits` wide window, then drop the value in.
			local shift = 32 - ebitPos
			data[i_word] = bor(band(data[i_word] or 0x0, bnot(blshift(brshift(b_mask, 32 - bits), shift))), blshift(int, shift))
			return self
		end

		-- Spans two words. bitPos is 1-31 here, so every shift below is in range.
		local overflow = ebitPos - 32 -- [[ 1, 31 ]]
		data[i_word] = bor(band(data[i_word] or 0x0, blshift(b_mask, 32 - bitPos)), brshift(int, overflow))
		data[i_word + 1] = bor(band(data[i_word + 1] or 0x0, brshift(b_mask, overflow)), blshift(int, 32 - overflow))

		return self
	end

	---@param self BitBuffer
	---@param bits number
	---@return number # The read data
	function readraw(self, bits)
		local tell = self._tell
		self._tell = tell + bits

		-- Retrive data pos
		local data = self._data
		local i_word = brshift(tell, 5) + 1 -- [ 1 - length ]
		local bitPos = band(tell, 31) -- [[ 0 - 31 ]]
		local ebitPos = bitPos + bits -- The end bit pos

		local n
		if ebitPos <= 32 then
			n = band(brshift(data[i_word] or 0x0, 32 - ebitPos), brshift(b_mask, 32 - bits))
		else
			local over = ebitPos - 32 -- How many bits we're over [[ 1, 31 ]]
			n = bor(blshift(band(data[i_word] or 0x0, brshift(b_mask, bitPos)), over), brshift(data[i_word + 1] or 0x0, 32 - over))
		end

		if self._little_endian and band(bits, 7) == 0 then
			n = brshift(bswap(n), 32 - bits)
		end

		return n
	end

	-- Raw (endian-agnostic) 32-bit word read/write. Same bit-merge math as readraw/writeraw
	-- with bits=32, but skips the little-endian swap check -- used to batch-move whole
	-- 4-byte groups (Read/ReadData/Write/WriteData) without a per-byte function call.

	---@param self BitBuffer
	---@return number
	function readraw32(self)
		local tell = self._tell
		self._tell = tell + 32

		local data = self._data
		local i_word = brshift(tell, 5) + 1
		local bitPos = band(tell, 31)

		if bitPos == 0 then
			return data[i_word] or 0x0
		end

		local n = bor(blshift(data[i_word] or 0x0, bitPos), brshift(data[i_word + 1] or 0x0, 32 - bitPos))
		return n
	end

	---@param self BitBuffer
	---@param int number
	function writeraw32(self, int)
		local tell = self._tell
		local newTell = tell + 32
		self._tell = newTell
		if newTell > self._len then self._len = newTell end

		local data = self._data
		local i_word = brshift(tell, 5) + 1
		local bitPos = band(tell, 31)

		if bitPos == 0 then
			data[i_word] = int
			return
		end

		data[i_word] = bor(band(data[i_word] or 0x0, blshift(b_mask, 32 - bitPos)), brshift(int, bitPos))
		data[i_word + 1] = bor(band(data[i_word + 1] or 0x0, brshift(b_mask, bitPos)), blshift(int, 32 - bitPos))
	end

	if not source:find("niknak") then return end
end

--- Add raw (debug) functions
meta._writeraw = writeraw
meta._readraw = readraw

-- Boolean
do
	--We don't need to call write/read raw. Since this is 1 bit.

	--- Writes a boolean.
	---@param b boolean
	---@return self BitBuffer
	function meta:WriteBoolean(b)
		local tell = self._tell
		local newTell = tell + 1
		self._tell = newTell
		if newTell > self._len then self._len = newTell end

		local data = self._data
		local i_word = brshift(tell, 5) + 1 -- [ 1 - length ]
		local mask = blshift(1, 31 - band(tell, 31)) -- The one bit we own

		if b then
			data[i_word] = bor(data[i_word] or 0x0, mask)
		else
			data[i_word] = band(data[i_word] or 0x0, bnot(mask))
		end

		return self
	end

	--- Reads a boolean.
	---@return boolean
	function meta:ReadBoolean()
		local tell = self._tell
		self._tell = tell + 1

		local word = self._data[brshift(tell, 5) + 1] or 0x0
		return band(word, blshift(1, 31 - band(tell, 31))) ~= 0
	end
end

local pow32 = math.pow(2, 32)

-- 32 bit Int
do
	meta.WriteInt = writeraw

	--- Reads an int.
	---@param bits number
	---@return number
	function meta:ReadInt(bits)
		local n = to_signed(readraw(self, bits), bits)
		return n
	end
end

-- UInt
do
	meta.WriteUInt = writeraw

	--- Reads an unsigned int.
	---@param bits number
	---@return number
	function meta:ReadUInt(bits)
		local n = readraw(self, bits)
		if n > -1 then return n end -- 32bit numbers could be negative when reading.
		return n + pow32
	end
end

-- Byte
do
	--- Writes a byte. ( 0 - 255 )
	---@param byte number
	---@return BitBuffer self
	function meta:WriteByte(byte)
		-- Fast path: the byte sits inside one word (a byte needs no endian swap).
		local tell = self._tell
		local bitPos = band(tell, 31)
		if bitPos <= 24 then
			local newTell = tell + 8
			self._tell = newTell
			if newTell > self._len then self._len = newTell end

			local data = self._data
			local i_word = brshift(tell, 5) + 1
			local shift = 24 - bitPos
			data[i_word] = bor(band(data[i_word] or 0x0, bnot(blshift(0xFF, shift))), blshift(band(byte, 0xFF), shift))
			return self
		end

		writeraw(self, byte, 8)
		return self
	end

	--- Reads a byte. ( 0 - 255 )
	---@return number
	function meta:ReadByte()
		-- Fast path: the byte sits inside one word (a byte needs no endian swap).
		local tell = self._tell
		local bitPos = band(tell, 31)
		local n
		if bitPos <= 24 then
			self._tell = tell + 8
			n = band(brshift(self._data[brshift(tell, 5) + 1] or 0x0, 24 - bitPos), 0xFF)
		else
			n = readraw(self, 8)
		end
		return n
	end
end

-- Signed Byte
do
	local WriteByte, ReadByte = meta.WriteByte, meta.ReadByte

	--- Writes a signed byte. ( -128 - 127 )
	---@param byte number
	---@return BitBuffer self
	meta.WriteSignedByte = WriteByte

	--- Reads a signed byte. ( -128 - 127 )
	---@return number
	function meta:ReadSignedByte()
		local n = ReadByte(self)
		if n >= 0x80 then return n - 0x100 end
		return n
	end
end

-- Ushort
do
	--- Writes an unsigned 2 byte number. ( 0 - 65535 )
	---@param num number
	---@return BitBuffer self
	function meta:WriteUShort(num)
		-- Fast path: little-endian and the short sits inside one word.
		local tell = self._tell
		local bitPos = band(tell, 31)
		if self._little_endian and bitPos <= 16 then
			local newTell = tell + 16
			self._tell = newTell
			if newTell > self._len then self._len = newTell end

			local data = self._data
			local i_word = brshift(tell, 5) + 1
			local shift = 16 - bitPos
			data[i_word] = bor(band(data[i_word] or 0x0, bnot(blshift(0xFFFF, shift))), blshift(brshift(bswap(num), 16), shift))
			return self
		end

		writeraw(self, num, 16)
		return self
	end

	--- Reads an unsigned 2 byte number. ( 0 - 65535 )
	---@return number
	function meta:ReadUShort()
		-- Fast path: little-endian and the short sits inside one word.
		local tell = self._tell
		local bitPos = band(tell, 31)
		local n
		if self._little_endian and bitPos <= 16 then
			self._tell = tell + 16
			local x = band(brshift(self._data[brshift(tell, 5) + 1] or 0x0, 16 - bitPos), 0xFFFF)
			n = brshift(bswap(x), 16)
		else
			n = readraw(self, 16)
		end
		return n
	end
end

-- Short
do
	local ReadUShort = meta.ReadUShort

	--- Writes a 2 byte number. ( -32768 - 32767 )
	---@param num number
	---@return BitBuffer self
	meta.WriteShort = meta.WriteUShort

	--- Reads a 2-byte signed number. ( -32768 - 32767 )
	---@return number
	function meta:ReadShort()
		local n = ReadUShort(self)
		if n >= 0x8000 then return n - 0x10000 end
		return n
	end
end

-- ULong
do
	--- Writes an unsigned 4 byte number. ( 0 - 4294967295 )
	---@param num number
	---@return self BitBuffer
	function meta:WriteULong(num)
		if self._little_endian then
			writeraw32(self, bswap(num))
		else
			writeraw32(self, bor(num, 0))
		end
		return self
	end

	--- Reads an unsigned 4 byte number ( 0 - 4294967295 )
	---@return number
	function meta:ReadULong()
		local n
		if self._little_endian then
			n = bswap(readraw32(self))
		else
			n = readraw(self, 32)
		end
		if n > -1 then return n end
		return n + pow32
	end
end

-- Long
do
	--- Writes a 4 byte number. ( -2147483648 - 2147483647 )
	---@param num number
	---@return BitBuffer self
	meta.WriteLong = meta.WriteULong

	--- Reads a 4 byte number. ( -2147483648 - 2147483647 )
	---@return number
	function meta:ReadLong()
		-- bswap already returns a signed 32-bit value.
		local n
		if self._little_endian then
			n = bswap(readraw32(self))
		else
			n = to_signed(readraw(self, 32), 32)
		end
		return n
	end
end

-- Nibble
do
	--- Writes a 4 bit unsigned number. ( 0 - 15 )
	---@param num number
	---@return BitBuffer self
	function meta:WriteNibble(num)
		writeraw(self, num, 4)
		return self
	end

	--- Reads a 4 bit unsigned number. ( 0 - 15 )
	---@return number
	function meta:ReadNibble()
		local n = readraw(self, 4)
		return n
	end
end

-- Snort ( 2bit number )
do
	--- Writes a 2 bit unsigned number. ( 0 - 3 )
	---@param num number
	---@return BitBuffer self
	function meta:WriteSnort(num)
		writeraw(self, num, 2)
		return self
	end

	--- Reads a 2 bit unsigned number. ( 0 - 3 )
	---@return number
	function meta:ReadSnort()
		local n = readraw(self, 2)
		return n
	end
end

local huge = math.huge
local INV_LN2 = 1 / log(2)

---@param x number
---@return number m
---@return number e
local function frexp2(x)
	local e = floor(log(x) * INV_LN2) + 1
	local m = ldexp(x, -e)
	-- log() can be one off right next to a power of two
	if m >= 1 then
		m = m * 0.5
		e = e + 1
	elseif m < 0.5 then
		m = m * 2
		e = e - 1
	end
	return m, e
end

-- Float
do
	--- Writes an IEEE 754 little-endian float.
	---@param num number
	---@return self BitBuffer
	function meta:WriteFloat(num)
		local sign = 0
		local bits -- exponent and mantissa, without the sign

		-- Mark negative numbers.
		if num < 0 then
			sign = 0x80000000
			num = -num
		end

		if num ~= num then -- Nan
			bits = 0x7F800001
		elseif num == huge then -- Infintiy
			bits = 0x7F800000
		elseif num ~= 0 then -- Anything but 0's
			local man, e = frexp2(num)
			local ex = e + 0x7E

			if ex <= 0 then
				-- Subnormal
				bits = floor(ldexp(man, ex + 23) + 0.5)
			else
				-- Adding (instead of or-ing) carries that into the exponent.
				bits = ex * 0x800000 + floor((man * 2 - 1) * 0x800000 + 0.5)
				if bits >= 0x7F800000 then bits = 0x7F800000 end -- Too large for a float: infinity
			end
		else
			bits = 0
			if 1 / num < 0 then sign = 0x80000000 end -- Minus 0 support
		end

		if self._little_endian then
			writeraw32(self, bswap(sign + bits))
		else
			writeraw32(self, bor(sign + bits, 0))
		end

		return self
	end

	-- pow2f[ex] is the weight of the lowest mantissa bit for the biased exponent ex
	local pow2f = {}
	for ex = 1, 254 do pow2f[ex] = ldexp(1, ex - 150) end
	local subnormal = ldexp(1, -149)

	--- Reads an IEEE 754 little-endian float.
	---@return number
	function meta:ReadFloat()
		-- Same bits as ReadULong, but skips the unsigned conversion and an extra call.
		local n
		if self._little_endian then
			n = bswap(readraw32(self))
		else
			n = readraw(self, 32)
		end
		local ex = band(brshift(n, 23), 0xFF)
		local man = band(n, 0x007FFFFF)

		local v
		if ex == 0 then
			v = man * subnormal -- Number 0 and subnormals
		elseif ex == 255 then
			if man ~= 0 then return 0 / 0 end -- nan
			v = huge -- -+inf
		else
			v = (man + 0x800000) * pow2f[ex]
		end

		if n < 0 then return -v end
		return v
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
	local _32pow = 2 ^ 32
	local _52pow = 2 ^ 52
	local _20pow = 2 ^ 20

	--- Writes an IEEE 754 little-endian double.
	---@param num number
	---@return BitBuffer self
	function meta:WriteDouble(num)
		-- Handle special cases first
		local sign = 0
		if num < 0 or (num == 0 and 1 / num < 0) then
			num = -num
			sign = 0x80000000
		end

		local ex, man_hi, man_lo
		if num == 0 then -- Zero
			ex, man_hi, man_lo = 0, 0, 0
		elseif num ~= num then -- NaN
			ex, man_hi, man_lo = 2047, 0, 1
		elseif num == huge then -- Infinity
			ex, man_hi, man_lo = 2047, 0, 0
		else
			local m, e = frexp2(num)
			ex = e + 1022
			if ex <= 0 then
				-- Subnormal: the 52 mantissa bits are num / 2^-1074, with no implicit leading 1
				m = ldexp(m, 20 + ex)
				ex = 0
			else
				m = (m * 2 - 1) * _20pow
			end
			man_hi = floor(m)
			man_lo = floor((m - man_hi) * _32pow + 0.5)
		end

		local hi = bor(sign, blshift(ex, 20), man_hi)
		if self._little_endian then
			writeraw32(self, bswap(man_lo))
			writeraw32(self, bswap(hi))
		else
			writeraw32(self, hi)
			writeraw32(self, bor(man_lo, 0))
		end

		return self
	end

	-- pow2d[ex] is the weight of the lowest mantissa bit for the biased exponent ex
	local pow2d = {}
	-- ldexp, not 2 ^ n: LuaJIT works x ^ -n out as 1 / x ^ n, which is 0 once 2 ^ n overflows
	for ex = 1, 2046 do pow2d[ex] = ldexp(1, ex - 1075) end
	local subnormal = ldexp(1, -1074)

	--- Reads an IEEE 754 little- or big-endian double.
	---@return number
	function meta:ReadDouble()
		local hi, lo
		if self._little_endian then
			lo = bswap(readraw32(self))
			hi = bswap(readraw32(self))
		else
			hi = readraw(self, 32)
			lo = readraw(self, 32)
		end
		if lo < 0 then lo = lo + _32pow end

		local ex = band(brshift(hi, 20), 0x7FF)
		local man = band(hi, 0x000FFFFF) * _32pow + lo -- All 52 mantissa bits; exact in a double

		local v
		if ex == 0 then
			v = man * subnormal -- ± Zero and subnormals
		elseif ex == 0x7FF then
			if man ~= 0 then return 0 / 0 end -- NaN
			v = huge -- Infinity
		else
			v = (man + _52pow) * pow2d[ex] -- Normal: (1.mantissa) * 2^(ex-1023)
		end

		if hi < 0 then return -v end
		return v
	end
end

-- Data
do
	--- Writes `len` bytes of `str`, packing each 4-byte group MSB-first (byte 1 = top byte).
	---@param self BitBuffer
	---@param str string
	---@param len number
	local function writeBytesBE(self, str, len)
		local q = lshift(rshift(len, 2), 2)

		for i = 1, q, 4 do
			local a, b, c, d = s_byte(str, i, i + 3)
			writeraw32(self, bor(lshift(a, 24), lshift(b, 16), lshift(c, 8), d))
		end

		for i = q + 1, len do
			self:WriteUInt(s_byte(str, i), 8)
		end
	end

	--- Writes `len` bytes of `str`, packing each 4-byte group reversed (byte 1 = bottom byte).
	---@param self BitBuffer
	---@param str string
	---@param len number
	local function writeBytesLE(self, str, len)
		local q = lshift(rshift(len, 2), 2)

		for i = 1, q, 4 do
			local a, b, c, d = s_byte(str, i, i + 3)
			writeraw32(self, bswap(bor(lshift(a, 24), lshift(b, 16), lshift(c, 8), d)))
		end

		for i = q + 1, len do
			self:WriteUInt(s_byte(str, i), 8)
		end
	end

	--- Reads `bytes` raw bytes back out (endian-agnostic; matches writeBytesBE's byte order).
	---@param self BitBuffer
	---@param bytes number
	---@return string
	local function readBytesRaw(self, bytes)
		local q = bytes - bytes % 4
		local parts, n = {}, 0

		-- Pull whole 4-byte groups in raw 32-bit reads instead of separate ReadByte calls and unpack them locally (same
		-- trick as IntToString).
		local i = 1
		local sixteen = q - q % 16
		while i <= sixteen do
			local w1, w2, w3, w4 = readraw32(self), readraw32(self), readraw32(self), readraw32(self)
			n = n + 1
			parts[n] = s_char(
				brshift(w1, 24), band(brshift(w1, 16), 0xFF), band(brshift(w1, 8), 0xFF), band(w1, 0xFF),
				brshift(w2, 24), band(brshift(w2, 16), 0xFF), band(brshift(w2, 8), 0xFF), band(w2, 0xFF),
				brshift(w3, 24), band(brshift(w3, 16), 0xFF), band(brshift(w3, 8), 0xFF), band(w3, 0xFF),
				brshift(w4, 24), band(brshift(w4, 16), 0xFF), band(brshift(w4, 8), 0xFF), band(w4, 0xFF))
			i = i + 16
		end

		while i <= q do
			local w = readraw32(self)
			n = n + 1
			parts[n] = s_char(brshift(w, 24), band(brshift(w, 16), 0xFF), band(brshift(w, 8), 0xFF), band(w, 0xFF))
			i = i + 4
		end

		local ReadByte = meta.ReadByte
		for _ = q + 1, bytes do
			n = n + 1
			parts[n] = s_char(ReadByte(self))
		end

		return ( table.concat(parts) )
	end

	--- Writes raw string-data.
	---@param str string
	---@return BitBuffer self
	function meta:Write(str)
		if self._little_endian then
			writeBytesLE(self, str, #str)
		else
			writeBytesBE(self, str, #str)
		end

		return self
	end

	--- Reads raw string-data. Default bytes are the length of the bitbuffer.
	---@param bytes number? If not given, will read until the end of the bitbuffer.
	---@return string
	function meta:Read(bytes)
		bytes = bytes or math.ceil((self:Size() - self:Tell()) / 8)
		return readBytesRaw(self, bytes)
	end

	--- Writes raw bytes directly, ignoring the endianness setting.
	---@param str string
	---@return BitBuffer
	function meta:WriteData(str)
		writeBytesBE(self, str, #str)
		return self
	end

	--- Reads raw bytes directly, ignoring the endianness setting.
	---@param bytes number
	---@return string
	function meta:ReadData(bytes)
		return readBytesRaw(self, bytes)
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

		if maxLength < 1 then return "" end

		local data, tell = self._data, self._tell
		local n = 0
		while n < maxLength do
			local t = tell + n * 8
			local bitPos = band(t, 31)
			local i_word = brshift(t, 5) + 1
			local c
			if bitPos <= 24 then
				c = band(brshift(data[i_word] or 0x0, 24 - bitPos), 0xFF)
			else
				local over = bitPos - 24
				c = band(bor(blshift(data[i_word] or 0x0, over), brshift(data[i_word + 1] or 0x0, 32 - over)), 0xFF)
			end
			if c == 0 then break end
			n = n + 1
		end

		local str = self:ReadData(n)
		self._tell = self._tell + 8 -- The terminator (or the byte after maxLength characters) is consumed as well

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