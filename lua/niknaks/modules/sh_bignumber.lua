local band, brshift, blshift, bor, bswap = bit.band, bit.rshift, bit.lshift, bit.bor, bit.bswap

---@class BigNumber
---@field x number
---@field y number
---@field z number
---@field w number  # High 32-bit word. Bit 31 is the sign bit (1 = negative), bits 0-30 are magnitude.
local meta = {}
meta.__index = meta

-- Bit 127 of the 128-bit value, stored as a signed int32 in w.
local SIGN_BIT = -2147483648 -- 0x80000000

local function isNeg(bn)
	return bn.w < 0
end
local function magW(w)
	return band(w, 0x7FFFFFFF)
end
local function stripSign(bn)
	if bn.w >= 0 then return bn end
	return setmetatable({ x = bn.x, y = bn.y, z = bn.z, w = magW(bn.w) }, meta)
end

--#region Compare operators

---'=' operator
---@param bNumber BigNumber|number
---@return boolean
function meta:__eq(bNumber)
	if isnumber(bNumber) then
		return magW(self.w) == 0 and self.y == 0 and self.z == 0 and self.x == bNumber
	end
	return self.x == bNumber.x and self.y == bNumber.y and self.z == bNumber.z and magW(self.w) == magW(bNumber.w)
end

---'<' operator
---@param bNumber BigNumber|number
---@return boolean
function meta:__lt(bNumber)
	if isnumber(bNumber) then
		return magW(self.w) == 0 and self.z == 0 and self.y == 0 and self.x < bNumber
	end
	local sw, bw = magW(self.w), magW(bNumber.w)
	if sw ~= bw then return sw < bw end
	if self.z ~= bNumber.z then return self.z < bNumber.z end
	if self.y ~= bNumber.y then return self.y < bNumber.y end
	return self.x < bNumber.x
end

---'<=' operator
---@param bNumber BigNumber|number
---@return boolean
function meta:__le(bNumber)
	if isnumber(bNumber) then
		return magW(self.w) == 0 and self.z == 0 and self.y == 0 and self.x <= bNumber
	end
	local sw, bw = magW(self.w), magW(bNumber.w)
	if sw ~= bw then return sw < bw end
	if self.z ~= bNumber.z then return self.z < bNumber.z end
	if self.y ~= bNumber.y then return self.y < bNumber.y end
	return self.x <= bNumber.x
end

--#endregion

--#region Operators

-- Bit fixer

---Shifts the bits to the right by the given amount.
---@param int integer
---@param shift integer
---@return integer
local function rshift(int, shift)
	if shift > 31 then return 0x0 end
	return brshift(int, shift)
end

---Shifts the bits to the left by the given amount.
---@param int integer
---@param shift integer
---@return integer
local function lshift(int, shift)
	if shift > 31 then return 0x0 end
	return blshift(int, shift)
end

---Double-precision right shift: shifts `lo` right by `shift`, filling from `hi`.
---@param lo integer
---@param hi integer
---@param shift integer
---@return integer
local function shrd(lo, hi, shift)
	if shift == 0 then return lo end
	if shift > 31 then return 0x0 end
	return bor(rshift(lo, shift), blshift(hi, 32 - shift))
end

---'<<' operator
---@param b number
---@return BigNumber
function meta:__shl(b)
	local res = setmetatable({ x = 0, y = 0, z = 0, w = 0 }, meta)
	if b >= 128 then
		return res
	elseif b <= 0 then
		res.x = self.x
		res.y = self.y
		res.z = self.z
		res.w = self.w
		return res
	elseif b >= 96 then
		res.x = 0
		res.y = 0
		res.z = 0
		res.w = lshift(self.x, (b - 96))
	elseif b >= 64 then
		b = b - 64
		res.x = 0
		res.y = 0
		res.z = lshift(self.x, b)
		res.w = bor(lshift(self.y, b), rshift(self.x, 32 - b))
	elseif b >= 32 then
		b = b - 32
		res.x = 0
		res.y = lshift(self.x, b)
		res.z = bor(lshift(self.y, b), rshift(self.x, 32 - b))
		res.w = bor(lshift(self.z, b), rshift(self.y, 32 - b))
	else
		res.x = lshift(self.x, b)
		res.y = bor(lshift(self.y, b), rshift(self.x, 32 - b))
		res.z = bor(lshift(self.z, b), rshift(self.y, 32 - b))
		res.w = bor(lshift(self.w, b), rshift(self.z, 32 - b))
	end
	return res
end

---'>>' operator
---@param b number
---@return BigNumber
function meta:__shr(b)
	local res = { x = 0, y = 0, z = 0, w = 0 }
	setmetatable(res, meta)

	if b < 32 then
		res.x = shrd(self.x, self.y, b)
		res.y = shrd(self.y, self.z, b)
		res.z = shrd(self.z, self.w, b)
		res.w = rshift(self.w, b)
	elseif b < 64 then
		res.x = shrd(self.y, self.z, (b - 32))
		res.y = shrd(self.z, self.w, (b - 32))
		res.z = rshift(self.w, (b - 32))
		res.w = 0
	elseif b < 96 then
		res.x = shrd(self.z, self.w, (b - 64))
		res.y = rshift(self.w, (b - 64))
		res.z = 0
		res.w = 0
	elseif b < 128 then
		res.x = rshift(self.w, (b - 96))
		res.y = 0
		res.z = 0
		res.w = 0
	end

	return res
end

---'~' operator
---@return BigNumber
function meta:__bnot()
	local res = { x = bit.bnot(self.x), y = bit.bnot(self.y), z = bit.bnot(self.z), w = bit.bnot(self.w) }
	setmetatable(res, meta)
	return res
end

---'&' operator
---@param b BigNumber
---@return BigNumber
function meta:__band(b)
	local res = {
		x = bit.band(self.x, b.x),
		y = bit.band(self.y, b.y),
		z = bit.band(self.z, b.z),
		w = bit.band(self.w,
			b.w)
	}
	setmetatable(res, meta)
	return res
end

---'|' operator
---@param b BigNumber
---@return BigNumber
function meta:__bor(b)
	local res = { x = bit.bor(self.x, b.x), y = bit.bor(self.y, b.y), z = bit.bor(self.z, b.z), w = bit.bor(self.w, b.w) }
	setmetatable(res, meta)
	return res
end

---'^' operator (bitwise XOR)
---@param b BigNumber
---@return BigNumber
function meta:__bxor(b)
	local res = {
		x = bit.bxor(self.x, b.x),
		y = bit.bxor(self.y, b.y),
		z = bit.bxor(self.z, b.z),
		w = bit.bxor(self.w,
			b.w)
	}
	setmetatable(res, meta)
	return res
end

--#endregion

-- Carry-ripple addition. Operates on unsigned magnitudes — callers must strip the sign bit first.
local function add(self, bNumber)
	self         = stripSign(self)
	bNumber      = stripSign(bNumber)
	local carry  = self:__band(bNumber)
	local result = self:__bxor(bNumber)
	local i      = 128
	while (carry.x ~= 0 or carry.y ~= 0 or carry.w ~= 0 or carry.z ~= 0) and i > 0 do
		local shiftedcarry = carry:__shl(1)
		carry = result:__band(shiftedcarry)
		result = result:__bxor(shiftedcarry)
		i = i - 1
	end
	return result
end

-- Two's-complement subtraction of unsigned magnitudes. Callers must strip sign first.
local function sub(self, bNumber)
	if isnumber(bNumber) then
		bNumber = NikNaks.BigNumber(bNumber --[[@as number]])
	end
	self         = stripSign(self)
	bNumber      = stripSign(bNumber)
	local notB   = bNumber:__bnot()
	local one    = setmetatable({ x = 1, y = 0, z = 0, w = 0 }, getmetatable(self))
	local result = add(self, add(notB, one))
	result.w     = magW(result.w)
	return result
end

---Adds two numbers together
---@param bNumber BigNumber|number
---@return BigNumber
function meta:__add(bNumber)
	if isnumber(bNumber) then
		bNumber = NikNaks.BigNumber(bNumber --[[@as number]])
	end
	if isNeg(self) ~= isNeg(bNumber) then
		return sub(self, bNumber)
	end
	return add(self, bNumber)
end

---'-' operator
---@param bNumber BigNumber|number
---@return BigNumber
function meta:__sub(bNumber)
	return sub(self, bNumber)
end

local function umul32(a, b)
	local a_lo = a % 0x10000
	local a_hi = math.floor(a / 0x10000)
	local b_lo = b % 0x10000
	local b_hi = math.floor(b / 0x10000)

	local mid = a_lo * b_hi + a_hi * b_lo -- bits 16-47, max ≈ 8.6e9

	local lo = a_lo * b_lo + (mid % 0x10000) * 0x10000
	local carry = math.floor(lo / 0x100000000)
	lo = lo % 0x100000000

	local hi = a_hi * b_hi + math.floor(mid / 0x10000) + carry

	return hi, lo
end

local function acc64(rx, ry, rz, rw, lo, hi, pos)
	local s, c
	if pos == 0 then
		s = rx + lo; rx = s % 0x100000000; c = math.floor(s / 0x100000000)
		s = ry + hi + c; ry = s % 0x100000000; c = math.floor(s / 0x100000000)
		s = rz + c; rz = s % 0x100000000; c = math.floor(s / 0x100000000)
		rw = (rw + c) % 0x100000000
	elseif pos == 1 then
		s = ry + lo; ry = s % 0x100000000; c = math.floor(s / 0x100000000)
		s = rz + hi + c; rz = s % 0x100000000; c = math.floor(s / 0x100000000)
		rw = (rw + c) % 0x100000000
	elseif pos == 2 then
		s = rz + lo; rz = s % 0x100000000; c = math.floor(s / 0x100000000)
		rw = (rw + hi + c) % 0x100000000
	elseif pos == 3 then
		rw = (rw + lo) % 0x100000000 -- hi lands at bit 128+, discarded
	end
	return rx, ry, rz, rw
end

---Multiplies two BigNumbers. Result is truncated to 128 bits.
---@param bNumber BigNumber|number
---@return BigNumber
function meta:__mul(bNumber)
	if isnumber(bNumber) then
		bNumber = NikNaks.BigNumber(bNumber --[[@as number]])
	end

	-- Work with unsigned magnitude bits only (strip sign from the high word).
	local ax = self.x % 0x100000000
	local ay = self.y % 0x100000000
	local az = self.z % 0x100000000
	local aw = magW(self.w) -- bits 0-30 of self.w only

	local bx = bNumber.x % 0x100000000
	local by = bNumber.y % 0x100000000
	local bz = bNumber.z % 0x100000000
	local bw = magW(bNumber.w) -- bits 0-30 of bNumber.w only

	local rx, ry, rz, rw = 0, 0, 0, 0
	local hi, lo

	hi, lo = umul32(ax, bx); rx, ry, rz, rw = acc64(rx, ry, rz, rw, lo, hi, 0)
	hi, lo = umul32(ax, by); rx, ry, rz, rw = acc64(rx, ry, rz, rw, lo, hi, 1)
	hi, lo = umul32(ay, bx); rx, ry, rz, rw = acc64(rx, ry, rz, rw, lo, hi, 1)
	hi, lo = umul32(ax, bz); rx, ry, rz, rw = acc64(rx, ry, rz, rw, lo, hi, 2)
	hi, lo = umul32(ay, by); rx, ry, rz, rw = acc64(rx, ry, rz, rw, lo, hi, 2)
	hi, lo = umul32(az, bx); rx, ry, rz, rw = acc64(rx, ry, rz, rw, lo, hi, 2)
	hi, lo = umul32(ax, bw); rx, ry, rz, rw = acc64(rx, ry, rz, rw, lo, hi, 3)
	hi, lo = umul32(ay, bz); rx, ry, rz, rw = acc64(rx, ry, rz, rw, lo, hi, 3)
	hi, lo = umul32(az, by); rx, ry, rz, rw = acc64(rx, ry, rz, rw, lo, hi, 3)
	hi, lo = umul32(aw, bx); rx, ry, rz, rw = acc64(rx, ry, rz, rw, lo, hi, 3)

	-- Convert unsigned accumulators to signed int32 (the bit-library format).
	if rx >= 0x80000000 then rx = rx - 0x100000000 end
	if ry >= 0x80000000 then ry = ry - 0x100000000 end
	if rz >= 0x80000000 then rz = rz - 0x100000000 end
	-- rw: clamp to 31-bit magnitude (bit 31 is reserved for the sign flag).
	rw = rw % 0x80000000

	-- Apply sign: negative iff exactly one operand is negative.
	local resultNeg = isNeg(self) ~= isNeg(bNumber)
	return setmetatable({
		x = rx,
		y = ry,
		z = rz,
		w = resultNeg and bor(rw, SIGN_BIT) or rw,
	}, meta)
end

---'^' operator — binary (fast) exponentiation, result truncated to 128 bits.
---@param exp BigNumber|number
---@return BigNumber
function meta:__pow(exp)
	local e
	if isnumber(exp) then
		e = math.floor(exp --[[@as number]])
	else
		e = (exp --[[@as BigNumber]]).x % 0x100000000
	end

	if e <= 0 then
		local v = e == 0 and 1 or 0
		return setmetatable({ x = v, y = 0, z = 0, w = 0 }, meta)
	end

	-- Binary exponentiation: O(log e) multiplications.
	-- __mul tracks the sign bit automatically, so initialise base with the real sign.
	local result = setmetatable({ x = 1, y = 0, z = 0, w = 0 }, meta)
	local base   = setmetatable({ x = self.x, y = self.y, z = self.z, w = self.w }, meta)

	while e > 0 do
		if e % 2 == 1 then
			result = result:__mul(base)
		end
		base = base:__mul(base)
		e = math.floor(e / 2)
	end

	return result
end

---Unsigned less-than comparison (ignores sign bit; compares raw magnitude).
---@param a BigNumber
---@param b BigNumber
---@return boolean
local function ult(a, b)
	local aw = magW(a.w); local bw = magW(b.w)
	if aw ~= bw then return aw < bw end
	local az = a.z % 0x100000000; local bz = b.z % 0x100000000
	if az ~= bz then return az < bz end
	local ay = a.y % 0x100000000; local by = b.y % 0x100000000
	if ay ~= by then return ay < by end
	return (a.x % 0x100000000) < (b.x % 0x100000000)
end

---Unsigned 128-bit division using Knuth's Algorithm D (base 2^16).
---@param a BigNumber
---@param b BigNumber
---@return BigNumber, BigNumber
local function divmod(a, b)
	-- Zero check on magnitude only (a negative zero is still zero).
	if b.x == 0 and b.y == 0 and b.z == 0 and magW(b.w) == 0 then
		return NikNaks.BigNumber(0), NikNaks.BigNumber(0)
	end

	-- Strip sign: division works on unsigned magnitudes; callers apply sign afterwards.
	a = stripSign(a)
	b = stripSign(b)

	-- Quick exit: a < b → quotient = 0, remainder = a.
	if ult(a, b) then
		return setmetatable({ x = 0, y = 0, z = 0, w = 0 }, meta),
		       setmetatable({ x = a.x, y = a.y, z = a.z, w = a.w }, meta)
	end

	local floor = math.floor
	local B     = 65536 -- 2^16

	local function unpack16(bn)
		local wx = bn.x % 0x100000000
		local wy = bn.y % 0x100000000
		local wz = bn.z % 0x100000000
		local ww = magW(bn.w)
		return {
			[0] = wx % B,        [1] = floor(wx / B),
			[2] = wy % B,        [3] = floor(wy / B),
			[4] = wz % B,        [5] = floor(wz / B),
			[6] = ww % B,        [7] = floor(ww / B),
		}
	end

	local function pack16(d)
		local wx = d[0] + d[1] * B
		local wy = d[2] + d[3] * B
		local wz = d[4] + d[5] * B
		local ww = d[6] + d[7] * B
		if wx >= 0x80000000 then wx = wx - 0x100000000 end
		if wy >= 0x80000000 then wy = wy - 0x100000000 end
		if wz >= 0x80000000 then wz = wz - 0x100000000 end
		return setmetatable({ x = wx, y = wy, z = wz, w = ww }, meta)
	end

	local vraw = unpack16(b)
	local n = 8
	while n > 1 and vraw[n - 1] == 0 do n = n - 1 end

	local vd = {}
	for i = 0, n - 1 do vd[i] = vraw[i] end

	local m = 8 - n -- a has m+n = 8 digits; quotient has m+1 digits.

	local d_norm = floor(B / (vd[n - 1] + 1))
	if d_norm > 1 then
		local carry = 0
		for i = 0, n - 1 do
			local p = vd[i] * d_norm + carry
			vd[i]   = p % B
			carry   = floor(p / B)
		end
	end

	local u = unpack16(a)
	u[8] = 0 -- u[m+n]
	if d_norm > 1 then
		local carry = 0
		for i = 0, 8 do
			local p = u[i] * d_norm + carry
			u[i]    = p % B
			carry   = floor(p / B)
		end
	end

	local q = {}
	for j = m, 0, -1 do
		local u_hi2 = u[j + n] * B + u[j + n - 1]
		local q_hat = floor(u_hi2 / vd[n - 1])
		local r_hat = u_hi2 % vd[n - 1]

		local vn2  = n >= 2 and vd[n - 2] or 0
		local ujn2 = j + n - 2 >= 0 and u[j + n - 2] or 0
		while q_hat >= B or q_hat * vn2 > B * r_hat + ujn2 do
			q_hat   = q_hat - 1
			r_hat   = r_hat + vd[n - 1]
			if r_hat >= B then break end
		end

		local borrow = 0
		for k = 0, n - 1 do
			local p    = q_hat * vd[k] + borrow
			local diff = u[j + k] - p % B
			if diff < 0 then
				u[j + k] = diff + B
				borrow    = floor(p / B) + 1
			else
				u[j + k] = diff
				borrow    = floor(p / B)
			end
		end
		u[j + n] = u[j + n] - borrow
		q[j] = q_hat

		if u[j + n] < 0 then
			q[j]        = q[j] - 1
			local carry = 0
			for k = 0, n - 1 do
				local s  = u[j + k] + vd[k] + carry
				u[j + k] = s % B
				carry     = floor(s / B)
			end
			u[j + n] = u[j + n] + carry
		end
	end

	local rd = {}
	if d_norm > 1 then
		local r = 0
		for i = n - 1, 0, -1 do
			local t = r * B + u[i]
			rd[i]   = floor(t / d_norm)
			r       = t % d_norm
		end
	else
		for i = 0, n - 1 do rd[i] = u[i] end
	end
	for i = n, 7 do rd[i] = 0 end
	for i = m + 1, 7 do q[i] = 0 end

	return pack16(q), pack16(rd)
end

---'/' operator — integer (floor) division.
---@param bNumber BigNumber|number
---@return BigNumber
function meta:__div(bNumber)
	if isnumber(bNumber) then
		bNumber = NikNaks.BigNumber(bNumber --[[@as number]])
	end
	local bn = bNumber --[[@as BigNumber]]
	local q = divmod(self, bn)
	-- Apply sign to result: negative iff exactly one operand is negative.
	local resultNeg = isNeg(self) ~= isNeg(bn)
	q.w = resultNeg and bor(magW(q.w), SIGN_BIT) or magW(q.w)
	return q
end

---'%' operator — remainder after integer division.
---The remainder carries the sign of the dividend (like C % behaviour).
---@param bNumber BigNumber|number
---@return BigNumber
function meta:__mod(bNumber)
	if isnumber(bNumber) then
		bNumber = NikNaks.BigNumber(bNumber --[[@as number]])
	end
	local _, r = divmod(self, bNumber --[[@as BigNumber]])
	-- Remainder carries the sign of the dividend.
	local resultNeg = isNeg(self)
	r.w = resultNeg and bor(magW(r.w), SIGN_BIT) or magW(r.w)
	return r
end

---Converts the 128-bit number to a decimal string.
---@return string
function meta:__tostring()
	local wx = self.x % 0x100000000
	local wy = self.y % 0x100000000
	local wz = self.z % 0x100000000
	local ww = magW(self.w) -- strip sign bit; treat as 31-bit magnitude

	if wx == 0 and wy == 0 and wz == 0 and ww == 0 then
		return "0"
	end

	local floor = math.floor
	local digits = {}

	while wx ~= 0 or wy ~= 0 or wz ~= 0 or ww ~= 0 do
		local rem = 0
		local combined

		combined = rem * 0x100000000 + ww
		ww = floor(combined / 10)
		rem = combined % 10
		combined = rem * 0x100000000 + wz
		wz = floor(combined / 10)
		rem = combined % 10
		combined = rem * 0x100000000 + wy
		wy = floor(combined / 10)
		rem = combined % 10
		combined = rem * 0x100000000 + wx
		wx = floor(combined / 10)
		rem = combined % 10

		-- rem is now the least-significant decimal digit of the remaining value
		digits[#digits + 1] = rem
	end

	-- Digits were produced least-significant first; reverse in-place before concat.
	local lo, hi = 1, #digits
	while lo < hi do
		digits[lo], digits[hi] = digits[hi], digits[lo]
		lo = lo + 1; hi = hi - 1
	end

	local str = table.concat(digits)
	return isNeg(self) and ("-" .. str) or str
end

---Creates a 128 bit bignumber
---@param number32Bit number|string
---@return BigNumber
local function BigNumber(number32Bit)
	if isstring(number32Bit) then
		local str = number32Bit --[[@as string]]
		local minus = str:sub(1, 1) == "-"
		local start = minus and 2 or 1

		-- Hex string: "0x..." / "0X..." / "-0x..."
		local prefix = str:sub(start, start + 1)
		if prefix == "0x" or prefix == "0X" then
			local hex = str:sub(start + 2)
			hex = string.rep("0", math.max(0, 32 - #hex)) .. hex
			local function h2i(s)
				local v = tonumber(s, 16) or 0
				if v >= 0x80000000 then v = v - 0x100000000 end
				return v
			end
			local ww = magW(h2i(hex:sub(#hex - 31, #hex - 24))) -- bits 96-126 (bit 31 reserved for sign)
			local wz = h2i(hex:sub(#hex - 23, #hex - 16))       -- bits 64-95
			local wy = h2i(hex:sub(#hex - 15, #hex - 8))        -- bits 32-63
			local wx = h2i(hex:sub(#hex - 7,  #hex))            -- bits 0-31
			if minus then ww = bor(ww, SIGN_BIT) end
			return setmetatable({ x = wx, y = wy, z = wz, w = ww }, meta)
		end

		-- Decimal string
		local t = setmetatable({ x = 0, y = 0, z = 0, w = 0 }, meta)
		local ten = setmetatable({ x = 10, y = 0, z = 0, w = 0 }, meta)

		for i = start, #str do
			local byte = str:byte(i)
			if byte < 48 or byte > 57 then break end -- stop on non-digit
			t = t:__mul(ten)
			local digit = setmetatable({ x = byte - 48, y = 0, z = 0, w = 0 }, meta)
			t = add(t, digit)
		end

		-- Store sign as bit 31 of w.
		if minus then t.w = bor(t.w, SIGN_BIT) end
		return t
	end

	local n = number32Bit --[[@as number]]
	local neg = n < 0
	local t = {
		x = math.abs(n),
		y = 0,
		z = 0,
		w = neg and SIGN_BIT or 0, -- sign bit lives in bit 31 of w
	}
	setmetatable(t, meta)
	return t
end

--- Creates a 128-bit signed integer. Accepts a 32-bit number, a decimal string, or a hex string ("0x…").
---@overload fun(number32Bit: number|string): BigNumber
NikNaks.BigNumber = setmetatable({}, {
	__call = function(_, ...) return BigNumber(...) end,
})

--- Writes all 128 bits to the active net message as four UInt32 values.
---@return BigNumber
function meta:WriteToNET()
	net.WriteUInt(self.x, 32)
	net.WriteUInt(self.y, 32)
	net.WriteUInt(self.z, 32)
	net.WriteUInt(self.w, 32)
	return self
end

--- Reads a BigNumber written by WriteToNET from the active net message.
---@return BigNumber
function NikNaks.BigNumber.ReadFromNET()
	local t = {
		x = net.ReadUInt(32),
		y = net.ReadUInt(32),
		z = net.ReadUInt(32),
		w = net.ReadUInt(32),
	}
	-- Convert unsigned 32-bit reads to signed int32 (matching the internal storage format).
	if t.x >= 0x80000000 then t.x = t.x - 0x100000000 end
	if t.y >= 0x80000000 then t.y = t.y - 0x100000000 end
	if t.z >= 0x80000000 then t.z = t.z - 0x100000000 end
	if t.w >= 0x80000000 then t.w = t.w - 0x100000000 end
	return setmetatable(t, meta)
end

-- Helper meta functions

---Adds a number to this BigNumber. Accepts BigNumber, number, or decimal/hex string.
---@param number BigNumber|number|string
---@return BigNumber
function meta:Add(number)
	if (isstring(number)) then
		number = NikNaks.BigNumber(number)
	end
	return self:__add(number --[[@as BigNumber|number]])
end

---Subtracts a number from this BigNumber. Accepts BigNumber, number, or decimal/hex string.
---@param number BigNumber|number|string
---@return BigNumber
function meta:Sub(number)
	if (isstring(number)) then
		number = NikNaks.BigNumber(number)
	end
	return self:__sub(number --[[@as BigNumber|number]])
end

---Multiplies this BigNumber by a number. Result is truncated to 128 bits. Accepts BigNumber, number, or decimal/hex string.
---@param number BigNumber|number|string
---@return BigNumber
function meta:Mul(number)
	if (isstring(number)) then
		number = NikNaks.BigNumber(number)
	end
	return self:__mul(number --[[@as BigNumber|number]])
end

---Divides this BigNumber by a number (integer floor division). Accepts BigNumber, number, or decimal/hex string.
---@param number BigNumber|number|string
---@return BigNumber
function meta:Div(number)
	if (isstring(number)) then
		number = NikNaks.BigNumber(number)
	end
	return self:__div(number --[[@as BigNumber|number]])
end

---Raises this BigNumber to a power. Result is truncated to 128 bits. Accepts BigNumber, number, or decimal/hex string.
---@param number BigNumber|number|string
---@return BigNumber
function meta:Pow(number)
	if (isstring(number)) then
		number = NikNaks.BigNumber(number)
	end
	return self:__pow(number --[[@as BigNumber|number]])
end

---Returns the remainder after dividing by a number (sign follows dividend). Accepts BigNumber, number, or decimal/hex string.
---@param number BigNumber|number|string
---@return BigNumber
function meta:Mod(number)
	if (isstring(number)) then
		number = NikNaks.BigNumber(number)
	end
	return self:__mod(number --[[@as BigNumber|number]])
end

--- Returns the lowest 32 bits as a signed Lua integer.
--- Values that exceed the 32-bit range are clamped to ±2147483647.
---@return integer
function meta:To32Bit()
	local neg = isNeg(self)
	if self.y ~= 0 or self.z ~= 0 or magW(self.w) ~= 0 then
		return neg and -2147483648 or 2147483647
	end
	if neg then
		return (self.x < 0) and -2147483648 or -self.x
	end
	return (self.x < 0) and 2147483647 or self.x
end

--- Returns the value as a 32-digit hex string, e.g. `"0x000000000000000000000000000000FF"`.
---@return string
function meta:ToHex()
	local wx = self.x % 0x100000000
	local wy = self.y % 0x100000000
	local wz = self.z % 0x100000000
	local ww = magW(self.w)
	local sign = isNeg(self) and "-" or ""
	return string.format("%s0x%08X%08X%08X%08X", sign, ww, wz, wy, wx)
end

---Returns true if the value equals zero.
---@return boolean
function meta:IsZero()
	return self.x == 0 and self.y == 0 and self.z == 0 and magW(self.w) == 0
end

---Returns true if the value is negative.
---@return boolean
function meta:IsNegative()
	return isNeg(self)
end

---Returns a new BigNumber with the absolute value.
---@return BigNumber
function meta:Abs()
	return setmetatable({ x = self.x, y = self.y, z = self.z, w = magW(self.w) }, meta)
end

---Returns a copy of this BigNumber.
---@return BigNumber
function meta:Copy()
	return setmetatable({ x = self.x, y = self.y, z = self.z, w = self.w }, meta)
end
