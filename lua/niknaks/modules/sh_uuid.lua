-- Copyright © 2022-2072, Nak, https://steamcommunity.com/id/Nak2/
-- All Rights Reserved. Not allowed to be reuploaded.

--- https://www.rfc-editor.org/rfc/rfc9562

--- Generates an RFC 9562 version 4 UUID
---@overload fun(): string
NikNaks.UUID = {}

local function fillRandomBytes(b, first, last)
	local i = first
	while i <= last do
		local n = NikNaks.Randomizer.GetSecureNumber()
		for _ = 1, 3 do
			if i > last then break end
			b[i] = n % 256
			n = math.floor(n / 256)
			i = i + 1
		end
	end
end

local function toHexString(b)
	local hex = {}
	for i = 1, 16 do hex[i] = string.format("%02x", b[i]) end

	return table.concat(hex, "", 1, 4) .. "-" ..
		table.concat(hex, "", 5, 6) .. "-" ..
		table.concat(hex, "", 7, 8) .. "-" ..
		table.concat(hex, "", 9, 10) .. "-" ..
		table.concat(hex, "", 11, 16)
end

local function generateUUIDv4()
	local b = {}
	fillRandomBytes(b, 1, 16)
	b[7] = bit.bor(bit.band(b[7], 0x0F), 0x40)
	b[9] = bit.bor(bit.band(b[9], 0x3F), 0x80)
	return toHexString(b)
end

--- The "empty UUID".
NikNaks.UUID.Empty = "00000000-0000-0000-0000-000000000000"

--- Generates a random RFC 9562 version 4 UUID.
---@return string
function NikNaks.UUID.V4()
	return generateUUIDv4()
end

local function unixMillis()
	return math.floor(os.time() * 1000 + (SysTime() % 1) * 1000)
end

local function timestampBytes(ms)
	local b = {}
	for i = 6, 1, -1 do
		b[i] = ms % 256
		ms = math.floor(ms / 256)
	end
	return b
end

--- Generates an RFC 9562 version 7 UUID (millisecond timestamp + random, sortable).
---@return string
function NikNaks.UUID.V7()
	local b = timestampBytes(unixMillis()) -- b[1..6]: 48-bit big-endian ms timestamp

	local randA = NikNaks.Randomizer.GetSecureNumber() % 4096 -- 12 random bits
	local randBHigh6 = NikNaks.Randomizer.GetSecureNumber() % 64 -- 6 random bits

	b[7] = bit.bor(0x70, bit.rshift(randA, 8)) -- version=7, top 4 bits of randA
	b[8] = bit.band(randA, 0xFF) -- bottom 8 bits of randA
	b[9] = bit.bor(0x80, randBHigh6) -- variant=10, top 6 bits of rand_b
	fillRandomBytes(b, 10, 16) -- remaining 56 bits of rand_b
	return toHexString(b)
end

local VALID_PATTERN = "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$"

--- Returns true if valid UUID
---@param str any
---@return boolean
function NikNaks.UUID.IsValid(str)
	return isstring(str) and string.match(str, VALID_PATTERN) ~= nil or false
end

setmetatable(NikNaks.UUID --[[@as table]], {
	__call = function(_) return generateUUIDv4() end,
})
