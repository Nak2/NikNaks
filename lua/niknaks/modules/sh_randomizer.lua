
--- Randomizer module
NikNaks.Randomizer = {}

---@class PRNGObject
---@field private state table
---@field private index number
local meta_prng = {}
meta_prng.__index = meta_prng

-- Constants
local N = 624
local M = 397
local UPPER_MASK = 0x80000000
local LOWER_MASK = 0x7FFFFFFF
local MATRIX_A = 0x9908B0DF
local TEMPERING_MASK_B = 0x9D2C5680
local TEMPERING_MASK_C = 0xEFC60000

local function xor_shift(seed)
    seed = bit.bxor(seed, bit.lshift(seed, 13))
    seed = bit.bxor(seed, bit.rshift(seed, 17))
    seed = bit.bxor(seed, bit.lshift(seed, 5))
    return seed
end

-- Lava lamp
local lava = 0

hook.Add("Move", "NikNaks.LavaLamp", function(_, mv)
    local seed = bit.bxor(bit.bxor(mv:GetForwardSpeed(), mv:GetSideSpeed()), mv:GetAngles().y)
    lava = xor_shift(bit.bxor(lava, seed))
end)

hook.Add("ShutDown", "NikNaks.LavaLamp", function()
    cookie.Set("niknaks.lavalamp", lava)
end)

---Generates a secure random number ( 0x00000000 -> 0x7FFFFFFF)
---@return number
function NikNaks.Randomizer.GetSecureNumber()
    local seed = os.time() -- Seed with current time
    seed = bit.bxor(seed, bit.lshift(seed, 11))
    seed = bit.bxor(seed, bit.rshift(seed, 8))
    seed = bit.bxor(seed, tonumber(tostring({}):sub(8), 16)) -- Mix in memory address as hexadecimal
    seed = xor_shift(seed) -- Further mixing with xor_shift
    seed = bit.bxor(seed, bit.lshift(seed, 11))
    seed = bit.bxor(seed, bit.rshift(seed, 8))
    seed = bit.bxor(seed, lava)

    return math.abs(seed % 0x7FFFFFFF)
end

lava = cookie.GetNumber("niknaks.lavalamp", NikNaks.Randomizer.SecureNumber())

---Generates an int from min to max
---@param min integer
---@param max integer
---@return integer
function NikNaks.Randomizer.GetInt(min, max)
    return math.min(max, math.max(min, math.floor(NikNaks.Randomizer.SecureNumber() % (max - min + 1) + min)))
end

---Generates a float from 0 to 1
---@return number
function NikNaks.Randomizer.GetFloat()
    return NikNaks.Randomizer.SecureNumber() / 0x7FFFFFFF
end

---Generates a float from min to max
---@param min number
---@param max number
---@return number
function NikNaks.Randomizer.GetFloatRange(min, max)
    return NikNaks.Randomizer.GetFloat() * (max - min) + min
end

---Creates a new PRNG object that utilizes the Mersenne Twister algorithm.
---@param seed number -- 32bit signed int.
---@return PRNGObject
function NikNaks.Randomizer.CreatePRNG(seed)
	local self = setmetatable({
		state = {},
		index = 0,
	}, meta_prng)
	self:SetSeed(seed)
    return self
end

---Sets the seed
---@param seed number
function meta_prng:SetSeed(seed)
	self.seed = seed
	self.index = 0
	for i = 0, 15 do
        self.state[i] = seed
        seed = bit.bxor(seed, bit.rshift(seed, 19))
        seed = bit.bxor(seed, bit.lshift(seed, 11))
        seed = bit.bxor(seed, bit.rshift(seed, 8))
        seed = bit.bxor(seed, bit.lshift(seed, 19))
    end
end

---Returns the seed
---@return number
function meta_prng:GetSeed()
	return self.seed
end

---Generates 32bit signed int from -2147483648 to 2147483647
---@return number
function meta_prng:Random()
	local a, b, c, d = self.state[self.index], self.state[(self.index + 13) % 16], self.state[(self.index + 9) % 16], self.state[(self.index + 5) % 16]
    local value = bit.bxor(a, bit.lshift(b, 16)) -- Construct a 32-bit value from two 16-bit parts
    local t = bit.bxor(c, bit.rshift(d, 4))
    local y1, y2 = bit.bxor(a, t), bit.bxor(bit.lshift(b, 11), bit.rshift(t, 7))

    self.state[self.index] = y2
    self.state[(self.index + 13) % 16] = y1
    self.state[(self.index + 9) % 16] = bit.bxor(t, bit.lshift(y1, 2))
    self.state[(self.index + 5) % 16] = bit.bxor(d, bit.rshift(y2, 8))

    self.index = (self.index + 15) % 16 -- Move to the next state

    return value
end

---Generates a random int from min to max
---@param min number
---@param max number
---@return number
function meta_prng:RandomRange(min, max)
	return math.min(max, self:Random() % (max - min + 1) + min)
end

---Generates a float from 0 to 1
---@return number
function meta_prng:RandomFloat()
	return (self:Random() + 2147483648) / 4294967295
end

---Generates a float from min to max
---@param min number
---@param max number
---@param decimals  number? Default 3
---@return number
function meta_prng:RandomFloatRange(min, max, decimals)
	return math.Round(self:RandomFloat() * (max - min) + min, decimals or 3)
end

---Creates a new PRNG object with a seed based on the current PRNG object.
---@return PRNGObject
function meta_prng:CreateNew()
    local rndVal = bit.bxor(self:Random(), bit.lshift(self:Random(), 16))
    return NikNaks.Randomizer.new(rndVal)
end