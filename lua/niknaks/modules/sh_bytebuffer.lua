-- Copyright © 2022-2072, Nak, https://steamcommunity.com/id/Nak2/
-- All Rights Reserved. Not allowed to be reuploaded.
local NikNaks = NikNaks
local s_char,s_byte, tostring, sub, string_reverse = string.char, string.byte, tostring, string.sub, string_reverse
local band, rshift, lshift, bor = bit.band, bit.rshift, bit.lshift, bit.bor
local ldexp, frexp, floor, min, ceil, max, rawget, setmetatable = math.ldexp, math.frexp, math.floor, math.min, math.ceil, math.max, rawget, setmetatable

--[[
	A bytebuffer object that allows read / write, and has all the functions of file.*
	Tested to be 40 - 80x faster than file.* functions.

	However will cost some CPU time to covert from string to byte.
	Tested to take about 3.5 seconds to load 1.5 GB string data.

	Also allows to read and write at the same time.
]]

-- Chops the number into byte numbers
local function _unpack( int, bytes )
	if 		bytes == 0 then return
	elseif 	bytes == 1 then return band( int, 0xFF )
	elseif	bytes == 2 then
		return band( rshift( int, 8), 0xFF ), band( int, 0xFF )
	elseif	bytes == 3 then
		return band( rshift( int, 16), 0xFF ), band( rshift( int, 8), 0xFF ), band( int, 0xFF )
	elseif	bytes == 4 then
		return band( rshift( int, 24), 0xFF ), band( rshift( int, 16), 0xFF ), band( rshift( int, 8), 0xFF ), band( int, 0xFF )
	end
	return "" -- 32 bit is max
end

-- Glues the string-byte back into a number
local function _pack( bytes, a, b, c, d )
	if bytes == 0 then return
	elseif bytes == 1 then return a
	elseif bytes == 2 then
		return bor( lshift( a, 8), b )
	elseif bytes == 3 then
		return bor( lshift( a, 16), lshift( b, 8), c )
	elseif bytes == 4 then
		return bor( lshift( a, 24), lshift( b, 16), lshift( c, 8), d )
	end
end

-- Pows
local maxint = {}
local subint = {}
for i = 1, 4 do
	local n = i * 8
	maxint[i] = math.pow(2, n - 1)
	subint[i] = math.pow(2, n)
end
local function to_signed( int, bytes )
	if int < 0 then return int end -- Already signed
	local maxint = maxint[bytes]
	return int - band(int,maxint) * 2
end
local function to_unsigned( int, bytes )
	return int >= 0 and int or int + subint[bytes]
end

--[[
	A special "empty" array of data that compresses the bytes written / read
	into a long 32byte int. Note: Unsafe int push
]]
local createDatastream, _ForcePush, _ForceRefresh,_writeDS, _readDS
do
	local datastream = {}
	datastream.__index = datastream
	-- Creates a new datastream array
	function createDatastream()
		local t = {}
		t._data = {}
		t._wbi = 0	-- Write Byte Index
		t._rbi = 0	-- Read Byte Index
		t._rba = {0x0, 0x0, 0x0, 0x0}
		t._wba = {0x0, 0x0, 0x0, 0x0}
		t._s = 0
		setmetatable(t, datastream)
		return t
	end
	-- Read
	function _readDS(self, pos)
		local _ip = floor( pos / 4 ) + 1 -- Int position in array [ 1 - E ]
		local _unpack = _unpack
		local _rba = self._rba
		if self._rbi ~= _ip then -- Load the new position data
			if _ip == self._wbi then -- We're reading from the writter
				local _wba = self._wba
				_rba[1] = _wba[1]
				_rba[2] = _wba[2]
				_rba[3] = _wba[3]
				_rba[4] = _wba[4]
			else -- Load from the packed data
				local a, b, c, d = _unpack(self._data[_ip] or 0x0000, 4)
				_rba[1] = a
				_rba[2] = b
				_rba[3] = c
				_rba[4] = d
			end
			self._rbi = _ip
		end
		return _rba[ pos % 4 + 1 ] or 0x0 -- Byte within int position [ 1 - 4 ]
	end
	-- Write Fast
	function _writeDS(self, pos, data)
		if not data then return end
		local _ip = floor( pos / 4 ) + 1 -- Int position in array [ 1 - E ]
		if self._wbi ~= _ip then -- Load a new position
			local _data = self._data
			-- Save all work
			_data[self._wbi] = _pack( 4, self._wba[1], self._wba[2], self._wba[3], self._wba[4] )
			-- Read new position data
			local a, b, c, d = _unpack(_data[_ip] or 0x0000, 4)
			self._wba[1] = a
			self._wba[2] = b
			self._wba[3] = c
			self._wba[4] = d
			self._wbi = _ip
		end
		local _bp = pos % 4 + 1 -- Byte position [ 1 - 4 ]
		if _ip == self._rbi then -- We're writting to the same read location. Copy the result into the read-header.
			self._rba[_bp] = data
		end
		self._wba[_bp] = data
		rawset(self,"_s", max( rawget(self,"_s") , pos ))
	end
	-- Write
	--function datastream.__newindexz(self, pos, data)
	--	if type(pos) ~= "number" then return rawset( self, pos, data) end
	--	if not data then return end
	--	assert(false, "AAAA")
	--	local _ip = floor( pos / 4 ) + 1 -- Int position in array [ 1 - E ]
	--	if self._wbi ~= _ip then -- Load a new position
	--		local _data = self._data
	--		-- Save all work
	--		_data[self._wbi] = _pack( 4, self._wba[1], self._wba[2], self._wba[3], self._wba[4] )
	--		-- Read new position data
	--		local a, b, c, d = _unpack(_data[_ip] or 0x0000, 4)
	--		self._wba[1] = a
	--		self._wba[2] = b
	--		self._wba[3] = c
	--		self._wba[4] = d
	--		self._wbi = _ip
	--	end
	--	local _bp = pos % 4 + 1 -- Byte position [ 1 - 4 ]
	--	if _ip == self._rbi then -- We're writting to the same read location. Copy the result into the read-header.
	--		self._rba[_bp] = data
	--	end
	--	self._wba[_bp] = data
	--	rawset(self,"_s", math.max( rawget(self,"_s") , pos ))
	--end
	-- ForcePush
	function _ForcePush(self)
		self._data[self._wbi] = _pack( 4, self._wba[1], self._wba[2], self._wba[3], self._wba[4] )
	end
	datastream._ForcePush = _ForcePush
	-- Force Refresh
	function _ForceRefresh(self, pos)
		local _ip = floor( pos / 4 ) + 1 -- Int position in array [ 1 - E ]
		local a, b, c, d = _unpack(self._data[_ip] or 0x0000, 4)
		self._rba[1] = a
		self._rba[2] = b
		self._rba[3] = c
		self._rba[4] = d
	end
	datastream._ForceRefresh = datastream
	-- Len ( When are we going to get # support? )
	function datastream.__len(self)
		return rawget(self,"_s") or 0
	end
end

--[[ DEBUG DATASTREAM
	local a = createDatastream()
	-- Test array
	for i = 1, 255 do
		a[i] = i
	end
	for i = 1, 255 do
		if i ~= a[i] then print("ERR") end
	end
	-- Test reading header
	for i = 1, 5 do
		a[255 + i] = i
		assert( a[255 + i]==i, "ERR" )
	end
	-- Make sure data stored is 32bit
	assert( rawget(a,"_data")[2] == 67174915, "ERR")
	-- Test modifying written bytes
	a[2] = 33
	a[5] = 55 -- Jump out to push number.
	assert(a[2] == 33, "ERR") --Jump in and mMake sure it changed
	assert(a:__len() == 260, "ERR") -- Higest written var is 260
--[[]]

local mName = "ByteBuffer"

---@class ByteBuffer
local meta = {}
meta.MetaName 	= mName
meta.__name 	= mName
meta.__index 	= meta
meta.__tostring = function(self) return "ByteBuffer Size: " .. self:Size() end
meta.__eq 		= function( self, other )
	if self:Size() ~= other:Size() then return false end
	local a, b = self:Tell(), other:Tell()
	self:Seek(0)
	other:Seek(0)
	local r = self:Read() == other:Read()
	self:Seek( a )
	other:Seek( b )
	return r
end
meta.__lt		= function(self, other ) -- <
	return self:Size() < other:Size()
end
meta.__le		= function(self, other ) -- <=
	return self:Size() <= other:Size()
end

NikNaks.ByteBuffer = {}

---Creates a string buffer.
---@param data? string
---@return ByteBuffer
function NikNaks.ByteBuffer.Create( data )
	local t = {}
	setmetatable(t, meta)
	t._data = createDatastream()
	t._wteller = 0
	t._rteller = 0
	if data then
		t:Write( data )
	end
	return t
end

---Converts a max 4 char string into an int.
---@param str string
---@return number
function NikNaks.ByteBuffer.StringToInt( str )
	local l = min(#str or "", 4)
	if l < 1 then 
		return 0
	elseif l < 2 then 
		return s_byte(str, 0, 1)
	end
	local a,b,c,d = s_byte( string_reverse( str ) , 0, l)
	local int = _pack(l, a, b, c, d)
	if int < 0 then int = bor(int, 0x80000000) end -- If it is lower than 0, that means we reached the 32bit negative-flag.
	return int
end

---Converts an int into into a string.
---@param int number
---@param bytes? number
---@return string
function NikNaks.ByteBuffer.IntToString( int, bytes )
	bytes = bytes or 4
	if bytes < 1 then return 0
	elseif bytes < 2 then return s_char( int ) end
	if int < 0 then int = bor(int, 0x80000000) end 
	return string_reverse( s_char( _unpack(int, bytes) ) )
end

-- Calling ByteBuffer, will create a new one.
setmetatable(NikNaks.ByteBuffer,{
	__call = function(_, data) return NikNaks.ByteBuffer.Create( data ) end
})

-- Writes a byte to said position
local function _writeByte(self, b, pos)
	local n = pos or self._wteller
	_writeDS(self._data, n, b)
	--self._data[n] = b
	self._wteller = n + 1
end

-- Reads a byte from said position
local function _readByte( self, pos )
	local n = pos or self._rteller
	self._rteller = n + 1
	return _readDS(self._data, n)
end

-- Write multiple
local function _write( self, a, b, c, d )
	local n = self._wteller
	if d then
		_writeDS(self._data,n,		d)
		_writeDS(self._data,n + 1, 	c)
		_writeDS(self._data,n + 2, 	b)
		_writeDS(self._data,n + 3, 	a)
		self._wteller = n + 4
	elseif c then
		_writeDS(self._data,n,		c )
		_writeDS(self._data,n+ 1, 	b )
		_writeDS(self._data,n+ 2, 	a )
		self._wteller = n + 3
	elseif b then
		_writeDS(self._data, n, b )
		_writeDS(self._data, n + 1, a )
		self._wteller = n + 2
	elseif a then
		_writeDS(self._data, n, a )
		self._wteller = n + 1
	end
end

-- Read multiple
local function _read( self, length )
	if length == 0 then return end
	local t = self._rteller
	self._rteller = self._rteller + length
	if length == 1 		then return _readDS(self._data,t)
	elseif length == 2 	then return _readDS(self._data,t + 1), _readDS(self._data,t)
	elseif length == 3 	then return _readDS(self._data,t + 2), _readDS(self._data,t + 1), _readDS(self._data,t)
	else					 return _readDS(self._data,t + 3), _readDS(self._data,t + 2), _readDS(self._data,t + 1), _readDS(self._data,t) end
end

-- Seek. Moves the teller / writter to byte position.
---@param pos number
---@param useWriter boolean
---@return self
function meta:Seek( pos, useWriter )
	if not useWriter then
		self._rteller = pos
	else
		self._wteller = pos
	end
	return self
end

---Returns the size of data.
---@return number
function meta:Size()
	return self._data:__len() + 1
end

---Returns the position of the teller / writter.
---@param useWriter boolean
---@return number
function meta:Tell( useWriter )
	if not useWriter then
		return self._rteller
	else
		return self._wteller
	end
end

---Skips x amount of bytes for the teller.
---@param amount number
---@return self
function meta:Skip( amount )
	self._rteller = self._rteller + amount
	return self
end

---Returns true if we reached the end of the data.
---@return boolean
function meta:EndOfData()
	return self:Tell() >= self:Size()
end

---Write Byte
---@param byte number
function meta:WriteByte( byte )
	_writeByte( self, byte )
end

---Read byte
---@return number
function meta:ReadByte()
	return _readByte( self )
end

local WriteByte = meta.WriteByte

---Write data
---@param str string
function meta:Write(str)
    local str_view_offset = 0
    local str_view_len = #str

    local s_byte = s_byte
    local WriteByte = WriteByte

    -- Save the string in chunks, if string is longer than 16 chars.
    if str_view_len >= 16 then
        local i = self._wteller
        -- To write directly into the array, we first need to fit the 32bit offset. Write the first few bytes.
        do
            local i_mod_4 = i % 4
            if i_mod_4 ~= 0 then
                local c = 4 - i_mod_4
                for v = 1, c do
                    WriteByte(self, s_byte(str, v))
                end
                do
                    str_view_offset = c
                end
                i = i + c
            end
        end
        local data = self._data
        _ForcePush(data) -- Make sure the header write last entry (If any)
        -- Write in chunks. This will speed it up.
        do
            local n = (ceil((str_view_len - str_view_offset) / 4) - 1) * 4
            do
                local t = data._data
                local c = #t
                local _pack = _pack
                for j = str_view_offset + 1, str_view_offset + n, 4 do
                    c = c + 1
                    t[c] = _pack(4, s_byte(str, j, j + 3))
                end
            end
            -- Cut off the bytes written
            do
                str_view_offset = str_view_offset + n
            end
            i = i + n
            self._wteller = i
        end
		if i > data._s then data._s = i end
        _ForceRefresh(data, self._rteller) -- Make sure the reader refreshes. Prob cheaper than to check every int32 we just dumped in.
    end
    -- Write the last few bytes into the header.
    for q = str_view_offset + 1, str_view_len do
        WriteByte(self, s_byte(str, q))
    end
end

---Read Data / String
---@param length number
---@return string
function meta:Read( length )
	local t = ""
	local length = min(length or (self:Size() - self:Tell()))
	if length > 8 then -- Read the data in chunks to speed it up.
		for i = 1, length / 4 do
			local a,b,c,d = _read(self, 4)
			t = t .. s_char( d,c,b,a )
			length = length - 4
		end
	end
	for i = 1, length do
		t = t .. s_char( _readByte( self ) )
	end
	return t
end

-- Type functions
do
-- Same as :Write, but uses the first two bytes to write the length of the string. Note; supports a max of 65535 charectors.
---@param str string
function meta:WriteString( str )
	if #str > 65535 then str = str:sub(0, 65535) end
	self:WriteUShort( #str )
	self:Write( str )
end

---Reads a string, using the first two bytes to get the length.
---@return string
function meta:ReadString()
	local t,n = "", self:ReadUShort() or 0
	for i = 1, n do
		t = t .. s_char( _readByte(self) )
	end
	return t
end
-- Boolean

---Writes a bool ( Takes up to 1 byte )
---@param bool boolean
function meta:WriteBool( bool )
	self:WriteByte( bool and 1 or 0 )
end

---Reads a bool
---@return boolean
function meta:ReadBool()
	return _readByte(self) == 1
end

-- UShort

---Writes a 16bit number.
	---@param int16 number
function meta:WriteUShort( int16 )
	_write(self, _unpack( int16, 2 ) )
end

---Reads a 16bit number.
---@return number
function meta:ReadUShort()
	return _pack( 2, _read(self, 2) )
end
-- Short

---Writes a 16bit number.
---@param int16 number
function meta:WriteShort( int16 )
		int16 = to_unsigned( int16, 2 ) or 0
		_write(self, _unpack( int16, 2 ) )
end

---Reads a 16bit number.
---@return number
function meta:ReadShort()
	return to_signed( _pack( 2, _read(self, 2) ) or 0, 2 )
end
-- ULong

-- Writes a 32bit number
---@param int32 number
function meta:WriteULong( int32 )
	_write(self, _unpack( int32, 4 ) )
end

---Reads a 32bit number
---@return number
function meta:ReadULong()
	local a,b,c,d = _read(self , 4)
	local int = _pack( 4, a,b,c,d )
	return to_unsigned(int, 4)
end
-- Long

-- Writes a signed 32bit number
---@param int32 number
function meta:WriteLong( int32 )
	if int32 < 0 then int32 = bor(int32, 0x80000000) end 
	_write(self, _unpack( int32, 4 ) )
end

---Reads a signed 32bit number
---@return number
function meta:ReadLong()
	return to_signed(_pack( 4, _read(self, 4) ), 4)
end
-- Nibble

---Writes two 4bit nibbles. A nibble can be a number between 0 and 15.
---@param int4 number
---@param int4_2? number
function meta:WriteNibble( int4, int4_2 )
	local a = band( int4	   ,0xF)		
	local b = band( int4_2 or 0,0xF)
	local r = bor(lshift(a,4), b )
	self:WriteByte( r)
end

---Reads two 4bit nibbles.
---@return number
function meta:ReadNibble()
	local n = _readByte(self)
	return rshift(n, 4), band(0xF, n)
end

-- Snort Also known as; crumb, quad, quarter, taste, tayste, tidbit, tydbit, lick, lyck, semi-nibble

---Writes 2bit ints into a byte. A 2bit number goes from 0 - 3
---@param int2 number
---@param int2_2? number
---@param int2_3? number
---@param int2_4? number
function meta:WriteSnort( int2, int2_2, int2_3, int2_4 )
	local a = band( int2	   ,0x03)		
	local b = band( int2_2 or 0,0x03)	
	local c = band( int2_3 or 0,0x03)	
	local d = band( int2_4 or 0,0x03)	
	self:WriteByte( bor(lshift(a,6), lshift(b,4),lshift(c,2), d) )
end

---Reads 4 snorts
---@return number
---@return number
---@return number
---@return number
function meta:ReadSnort()
	local n = _readByte(self)
	local a = rshift( band( n,0xC0), 6)		
	local b = rshift( band( n,0x30), 4)
	local c = rshift( band( n,0x0C), 2)
	local d = band( n,0x03)
	return a, b, c, d
end

-- Float types

---Writes a float
---@param number number
function meta:WriteFloat( number )
	local sign = 0
	local man = 0
	local ex = 0
	-- Mark negative numbers.
	if number < 0 then
		sign = 0x80000000
		number = -number
	end
	if number ~= number then -- Nan
		ex = 0xFF
		man = 1
	elseif number == math.huge then -- Infintiy
		ex = 0xFF
		man = 0
	elseif number ~= 0 then -- Anything but 0's
		man, ex = frexp(number)
		ex = ex + 0x7F
		if ex <= 0 then
			man = ldexp( man, ex - 1 )
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
	elseif tostring(number) == "-0" then -- Minus 0 support
		sign = 0x80000000
	end
	man = floor(ldexp(man, 23) + 0.5)
	self:WriteULong( bor( sign, lshift(band(ex, 0xFF), 23), man ) )
end

local _23pow = 2 ^ 23
function meta:ReadFloat()
	local n = self:ReadULong()
	local sign = band(0x80000000, n) == 0 and 1 or -1
	local ex = band(rshift(n, 23),0xFF)
	local man = band(n, 0x007FFFFF) / _23pow
	if ex == 0 and man == 0 then return 0 * sign				-- Number 0
	elseif ex == 255 and man == 0 then return math.huge * sign 	-- -+inf
	elseif ex == 255 and man ~= 0 then return 0/0				-- nan
	else return ldexp (1 + man, ex - 127) * sign end	
end

--[[
	TODO: Add Double
]]

-- Special Types

---Writes a vector
---@param vector Vector
function meta:WriteVector( vector )
	self:WriteFloat( vector.x )
	self:WriteFloat( vector.y )
	self:WriteFloat( vector.z )
end

---Reads a vector
---@return Vector
function meta:ReadVector()
	local x = self:ReadFloat()
	local y = self:ReadFloat()
	local z = self:ReadFloat()
	return Vector(x, y, z)
end

---Writes an angle
---@param angle Angle
function meta:WriteAngle( angle )
	self:WriteFloat( angle.p )
	self:WriteFloat( angle.y )
	self:WriteFloat( angle.r )
end

---Reads an angle
---@return Angle
function meta:ReadAngle()
	local p = self:ReadFloat()
	local y = self:ReadFloat()
	local r = self:ReadFloat()
	return Angle(p, y, r)
end

---Writes a 32bit color
---@param color Color
function meta:WriteColor( color )
	self:WriteByte( color.r )
	self:WriteByte( color.g )
	self:WriteByte( color.b )
	self:WriteByte( color.a or 255 )
end

---Reads a 32bit color
---@return Color
function meta:ReadColor( )
	local r = _readByte(self)
	local g = _readByte(self)
	local b = _readByte(self)
	local a = _readByte(self)
	return Color( r, g, b, a )
end

---Writes a signed charector. ( -128 to 127 )
---@param number number
function meta:WriteSignedByte( number )
	if var < 0 or var > 127 then
		var = bor(band(var, 0x7F), 0x80)
	else
		var = band(var, 0x7F)
	end
	_writeByte( self, var )
end

---Reads a signed charector. ( -128 to 127 )
---@return number
function meta:ReadSignedByte()
	local b = _readByte( self )
	local n = band(b, 0x80) == 0 and 1 or -1
	return band(b, 0x7F) * n
end

end

-- Clears data
function meta:Clear()
	self._data = createDatastream()
	self._wteller = 0
	self._rteller = 0
end

-- File <-> ByteBuffer
do
	---Same as file.Open, but returns it as a bytebuffer.
	---@param fileName string
	---@param gamePath? string
	---@param lzma? boolean
	---@return ByteBuffer
	function NikNaks.ByteBuffer.OpenFile( fileName, gamePath, lzma )
		if ( gamePath == true ) then gamePath = "GAME" end
		if ( gamePath == nil or gamePath == false ) then gamePath = "DATA" end
		local f = file.Open( fileName, "rb", gamePath )
		if not f then return end
		-- Data
		local str = f:Read( f:Size() ) -- Is faster
		if lzma then
			str = util.Decompress( str ) or str
		end
		local b = NikNaks.ByteBuffer(str)
		f:Close()
		return b
	end

	---Saves the buffer to a file within the data folder.
	---@param fileName string
	---@param lzma? boolean
	---@return boolean
	function meta:SaveToFile( fileName, lzma )
		local f = file.Open( fileName, "wb", "DATA" )
		if not f then return false end
		local s = self:Size()
		local t = self:Tell()
		self:Seek( 0 ) -- Reset the reader
		if not lzma then
			local n = math.floor( s / 4 ) -- Amount of "chunks"
			for i = 1, n do
				f:WriteLong( self:ReadLong() )
				s = s - 4
			end
			-- Write the last bytes
			for i = 1, s do
				f:WriteByte( _readByte(self) )
			end
		else
			local data = self:Read()
			data = util.Compress( data )
			f:Write(data)
		end
		self:Seek( t )
		f:Close()
		return true
	end
end

--[[ Valve Alias
	Not 100% regarding GetChar / PutChar
]]
meta.GetUnsignedChar	= meta.ReadByte		-- Why?
meta.GetUnsignedShort	= meta.ReadUShort
meta.GetUnsignedInt		= meta.ReadULong
meta.PutUnsignedChar	= meta.WriteByte
meta.PutUnsignedShort	= meta.WriteUShort
meta.PutUnsignedInt		= meta.WriteULong

meta.GetShort	= meta.ReadShort
meta.GetInt		= meta.ReadLong
meta.GetChar	= meta.ReadSignedByte		-- I have no idea if this is signed. It would explain some crazy bools in the files.
meta.PutShort	= meta.WriteShort
meta.PutInt		= meta.WriteLong
meta.PutChar 	= meta.WriteSignedByte