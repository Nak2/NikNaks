-- Unit tests for the BigNumber module (sh_bignumber.lua)
-- BigNumber stores a 128-bit integer as four signed int32 words:
--   value = x  +  y*2^32  +  z*2^64  +  w*2^96
-- The bit library uses signed int32, so 0x80000000 is stored as -2147483648.
-- __tostring converts via % 0x100000000 to get the true unsigned value.

local BN   = 0 -- filled in init
local MASK = 0x80000000 -- -2147483648 as signed int32, represents bit 31

--- Build a BigNumber from four explicit 32-bit words without going through the
--- constructor's 32-bit clamped path.
local function bn(x, y, z, w)
    local t = BN(0)
    t.x = x or 0
    t.y = y or 0
    t.z = z or 0
    t.w = w or 0
    return t
end

return {
    groupname = "BigNumber",
    init = function()
        Should(_UNITTEST)
            :WithMessage("Unit test flag not set")
            .And:BeTrue()

        require("niknaks")

        Should(NikNaks.BigNumber):Exist()
            .And:BeOfType("table")

        BN = NikNaks.BigNumber
    end,
    cases = {

        -- ────────────────────────────────────────────────────────────────
        -- __tostring
        -- ────────────────────────────────────────────────────────────────

        {
            name = "tostring: 0",
            func = function()
                Should( tostring( BN(0) ) ):Be("0")
            end
        },
        {
            name = "tostring: 1",
            func = function()
                Should( tostring( BN(1) ) ):Be("1")
            end
        },
        {
            name = "tostring: max positive int32 (2147483647)",
            func = function()
                Should( tostring( BN(2147483647) ) ):Be("2147483647")
            end
        },
        {
            name = "tostring: max uint32 (0xFFFFFFFF via x=-1)",
            func = function()
                -- 0xFFFFFFFF = 4294967295, stored as -1 in signed int32
                Should( tostring( bn(-1) ) ):Be("4294967295")
            end
        },
        {
            name = "tostring: 2^32 (y=1)",
            func = function()
                Should( tostring( bn(0, 1) ) ):Be("4294967296")
            end
        },
        {
            name = "tostring: 2^64 (z=1)",
            func = function()
                Should( tostring( bn(0, 0, 1) ) ):Be("18446744073709551616")
            end
        },
        {
            name = "tostring: 2^96 (w=1)",
            func = function()
                Should( tostring( bn(0, 0, 0, 1) ) ):Be("79228162514264337593543950336")
            end
        },

        -- ────────────────────────────────────────────────────────────────
        -- __shl  (left shift)
        -- ────────────────────────────────────────────────────────────────

        {
            name = "shl: by 0 is identity",
            func = function()
                local r = bn(7, 3, 5, 2):__shl(0)
                Should(r.x):Be(7)
                Should(r.y):Be(3)
                Should(r.z):Be(5)
                Should(r.w):Be(2)
            end
        },
        {
            name = "shl: 1 << 1 = 2",
            func = function()
                local r = bn(1):__shl(1)
                Should(r.x):Be(2)
                Should(r.y):Be(0)
                Should(r.z):Be(0)
                Should(r.w):Be(0)
            end
        },
        {
            name = "shl: 1 << 31 fills high bit of x word",
            func = function()
                -- 0x80000000 = -2147483648 as signed int32
                local r = bn(1):__shl(31)
                Should(r.x):Be(-2147483648)
                Should(r.y):Be(0)
                Should(r.z):Be(0)
                Should(r.w):Be(0)
            end
        },
        {
            name = "shl: 1 << 32 moves into y word",
            func = function()
                local r = bn(1):__shl(32)
                Should(r.x):Be(0)
                Should(r.y):Be(1)
                Should(r.z):Be(0)
                Should(r.w):Be(0)
            end
        },
        {
            name = "shl: carry propagates from x into y",
            func = function()
                -- 0x80000000 << 1: high bit of x overflows into low bit of y
                local r = bn(-2147483648):__shl(1)
                Should(r.x):Be(0)
                Should(r.y):Be(1)
                Should(r.z):Be(0)
                Should(r.w):Be(0)
            end
        },
        {
            name = "shl: 0xFFFFFFFF << 1 spans x and y",
            func = function()
                -- 0xFFFFFFFF << 1:
                --   x = 0xFFFFFFFE = -2   (bits 1-31 of x)
                --   y = 1                  (bit 32, carried from bit 31)
                local r = bn(-1):__shl(1)
                Should(r.x):Be(-2)   -- 0xFFFFFFFE
                Should(r.y):Be(1)
                Should(r.z):Be(0)
                Should(r.w):Be(0)
            end
        },
        {
            name = "shl: 1 << 64 moves into z word",
            func = function()
                local r = bn(1):__shl(64)
                Should(r.x):Be(0)
                Should(r.y):Be(0)
                Should(r.z):Be(1)
                Should(r.w):Be(0)
            end
        },
        {
            name = "shl: carry propagates from y into z",
            func = function()
                -- y = 0x80000000, shift left by 1: low bit of z gets 1
                local r = bn(0, -2147483648):__shl(1)
                Should(r.x):Be(0)
                Should(r.y):Be(0)
                Should(r.z):Be(1)
                Should(r.w):Be(0)
            end
        },
        {
            name = "shl: 1 << 96 moves into w word",
            func = function()
                local r = bn(1):__shl(96)
                Should(r.x):Be(0)
                Should(r.y):Be(0)
                Should(r.z):Be(0)
                Should(r.w):Be(1)
            end
        },
        {
            name = "shl: carry propagates from z into w",
            func = function()
                -- z = 0x80000000, shift left by 1: low bit of w gets 1
                local r = bn(0, 0, -2147483648):__shl(1)
                Should(r.x):Be(0)
                Should(r.y):Be(0)
                Should(r.z):Be(0)
                Should(r.w):Be(1)
            end
        },
        {
            name = "shl: 1 << 127 sets only highest bit",
            func = function()
                local r = bn(1):__shl(127)
                Should(r.x):Be(0)
                Should(r.y):Be(0)
                Should(r.z):Be(0)
                Should(r.w):Be(-2147483648) -- 0x80000000
            end
        },
        {
            name = "shl: 1 << 128 gives zero",
            func = function()
                local r = bn(1):__shl(128)
                Should(r.x):Be(0)
                Should(r.y):Be(0)
                Should(r.z):Be(0)
                Should(r.w):Be(0)
            end
        },
        {
            name = "shl: all-ones << 32 shifts every word up",
            func = function()
                -- {x=-1, y=-1, z=-1, w=-1} << 32:
                --   new_x = 0
                --   new_y = old_x = -1
                --   new_z = old_y = -1
                --   new_w = old_z = -1  (old_w is lost, it overflows out)
                local r = bn(-1, -1, -1, -1):__shl(32)
                Should(r.x):Be(0)
                Should(r.y):Be(-1)
                Should(r.z):Be(-1)
                Should(r.w):Be(-1)
            end
        },

        -- ────────────────────────────────────────────────────────────────
        -- __shr  (right shift)
        -- ────────────────────────────────────────────────────────────────

        {
            name = "shr: by 0 is identity",
            func = function()
                local r = bn(7, 3, 5, 2):__shr(0)
                Should(r.x):Be(7)
                Should(r.y):Be(3)
                Should(r.z):Be(5)
                Should(r.w):Be(2)
            end
        },
        {
            name = "shr: 4 >> 1 = 2",
            func = function()
                local r = bn(4):__shr(1)
                Should(r.x):Be(2)
                Should(r.y):Be(0)
            end
        },
        {
            name = "shr: carry propagates from y into x",
            func = function()
                -- y = 1, shift right by 1: low bit of y moves to high bit of x
                local r = bn(0, 1):__shr(1)
                Should(r.x):Be(-2147483648) -- 0x80000000
                Should(r.y):Be(0)
                Should(r.z):Be(0)
                Should(r.w):Be(0)
            end
        },
        {
            name = "shr: y=1 >> 32 moves into x",
            func = function()
                local r = bn(0, 1):__shr(32)
                Should(r.x):Be(1)
                Should(r.y):Be(0)
                Should(r.z):Be(0)
                Should(r.w):Be(0)
            end
        },
        {
            name = "shr: carry propagates from z into y",
            func = function()
                -- z = 1, shift right by 1: low bit of z moves to high bit of y
                local r = bn(0, 0, 1):__shr(1)
                Should(r.x):Be(0)
                Should(r.y):Be(-2147483648) -- 0x80000000
                Should(r.z):Be(0)
                Should(r.w):Be(0)
            end
        },
        {
            name = "shr: z=1 >> 64 moves into x",
            func = function()
                local r = bn(0, 0, 1):__shr(64)
                Should(r.x):Be(1)
                Should(r.y):Be(0)
                Should(r.z):Be(0)
                Should(r.w):Be(0)
            end
        },
        {
            name = "shr: carry propagates from w into z",
            func = function()
                -- w = 1, shift right by 1: low bit of w moves to high bit of z
                local r = bn(0, 0, 0, 1):__shr(1)
                Should(r.x):Be(0)
                Should(r.y):Be(0)
                Should(r.z):Be(-2147483648) -- 0x80000000
                Should(r.w):Be(0)
            end
        },
        {
            name = "shr: w=1 >> 96 moves into x",
            func = function()
                local r = bn(0, 0, 0, 1):__shr(96)
                Should(r.x):Be(1)
                Should(r.y):Be(0)
                Should(r.z):Be(0)
                Should(r.w):Be(0)
            end
        },
        {
            name = "shr: highest bit >> 127 leaves only lowest bit",
            func = function()
                -- w = 0x80000000: only the top bit of the 128-bit number is set
                local r = bn(0, 0, 0, -2147483648):__shr(127)
                Should(r.x):Be(1)
                Should(r.y):Be(0)
                Should(r.z):Be(0)
                Should(r.w):Be(0)
            end
        },
        {
            name = "shr: all-ones >> 32 shifts every word down",
            func = function()
                -- {x=-1, y=-1, z=-1, w=-1} >> 32:
                --   new_x = old_y = -1
                --   new_y = old_z = -1
                --   new_z = old_w = -1
                --   new_w = 0      (high bits don't fill in)
                local r = bn(-1, -1, -1, -1):__shr(32)
                Should(r.x):Be(-1)
                Should(r.y):Be(-1)
                Should(r.z):Be(-1)
                Should(r.w):Be(0)
            end
        },

        -- ────────────────────────────────────────────────────────────────
        -- Roundtrip: shl then shr should recover the original value
        -- ────────────────────────────────────────────────────────────────

        {
            name = "roundtrip: shl(33) then shr(33)",
            func = function()
                local orig = bn(0xBEEF)
                local r = orig:__shl(33):__shr(33)
                Should(r.x):Be(orig.x)
                Should(r.y):Be(0)
                Should(r.z):Be(0)
                Should(r.w):Be(0)
            end
        },
        {
            name = "roundtrip: shl(65) then shr(65)",
            func = function()
                local orig = bn(12345)
                local r = orig:__shl(65):__shr(65)
                Should(r.x):Be(orig.x)
                Should(r.y):Be(0)
                Should(r.z):Be(0)
                Should(r.w):Be(0)
            end
        },
        {
            name = "roundtrip: shl(97) then shr(97)",
            func = function()
                local orig = bn(99)
                local r = orig:__shl(97):__shr(97)
                Should(r.x):Be(orig.x)
                Should(r.y):Be(0)
                Should(r.z):Be(0)
                Should(r.w):Be(0)
            end
        },

        -- ────────────────────────────────────────────────────────────────
        -- __add  (addition with overflow / carry)
        -- ────────────────────────────────────────────────────────────────

        {
            name = "add: simple 3 + 4 = 7",
            func = function()
                local r = BN(3) + BN(4)
                Should(r.x):Be(7)
                Should(r.y):Be(0)
                Should(r.z):Be(0)
                Should(r.w):Be(0)
            end
        },
        {
            name = "add: 32-bit overflow carries into y (0xFFFFFFFF + 1)",
            func = function()
                -- 0xFFFFFFFF + 1 = 2^32; x rolls to 0, y becomes 1
                local r = bn(-1) + BN(1)
                Should(r.x):Be(0)
                Should(r.y):Be(1)
                Should(r.z):Be(0)
                Should(r.w):Be(0)
            end
        },
        {
            name = "add: 64-bit overflow carries into z",
            func = function()
                -- (2^64 - 1) + 1 = 2^64; x=0, y=0, z=1
                local r = bn(-1, -1) + BN(1)
                Should(r.x):Be(0)
                Should(r.y):Be(0)
                Should(r.z):Be(1)
                Should(r.w):Be(0)
            end
        },
        {
            name = "add: 96-bit overflow carries into w",
            func = function()
                -- (2^96 - 1) + 1 = 2^96; x=y=z=0, w=1
                local r = bn(-1, -1, -1) + BN(1)
                Should(r.x):Be(0)
                Should(r.y):Be(0)
                Should(r.z):Be(0)
                Should(r.w):Be(1)
            end
        },
        {
            name = "add: negative + positive subtracts magnitudes",
            func = function()
                -- bn(-1,-1,-1,-1) has the sign bit set in w (w=-1 < 0), so it
                -- represents -(2^127-1) in sign-magnitude form.
                -- -(2^127-1) + 1  →  |result| = (2^127-1) - 1 = 2^127-2, positive.
                -- 2^127-2 = 0x7FFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFE
                local r = bn(-1, -1, -1, -1) + BN(1)
                Should(r.x):Be(-2)          -- 0xFFFFFFFE
                Should(r.y):Be(-1)          -- 0xFFFFFFFF
                Should(r.z):Be(-1)          -- 0xFFFFFFFF
                Should(r.w):Be(2147483647)  -- 0x7FFFFFFF (sign bit clear)
            end
        },
        {
            name = "add: tostring 2^32 via overflow",
            func = function()
                local r = bn(-1) + BN(1)
                Should( tostring(r) ):Be("4294967296")
            end
        },

        -- ────────────────────────────────────────────────────────────────
        -- __sub  (subtraction with borrow)
        -- ────────────────────────────────────────────────────────────────

        {
            name = "sub: simple 10 - 3 = 7",
            func = function()
                local r = BN(10) - BN(3)
                Should(r.x):Be(7)
                Should(r.y):Be(0)
                Should(r.z):Be(0)
                Should(r.w):Be(0)
            end
        },
        {
            name = "sub: 32-bit borrow (2^32 - 1 = 0xFFFFFFFF)",
            func = function()
                -- bn(0,1) = 2^32; subtract 1 → x = -1 (0xFFFFFFFF), y = 0
                local r = bn(0, 1) - BN(1)
                Should(r.x):Be(-1)  -- 0xFFFFFFFF as signed int32
                Should(r.y):Be(0)
                Should(r.z):Be(0)
                Should(r.w):Be(0)
                Should( tostring(r) ):Be("4294967295")
            end
        },
        {
            name = "sub: 64-bit borrow (2^64 - 1)",
            func = function()
                -- bn(0,0,1) = 2^64; subtract 1 → x=-1, y=-1, z=0
                local r = bn(0, 0, 1) - BN(1)
                Should(r.x):Be(-1)
                Should(r.y):Be(-1)
                Should(r.z):Be(0)
                Should(r.w):Be(0)
                Should( tostring(r) ):Be("18446744073709551615")
            end
        },
        {
            name = "sub: 96-bit borrow (2^96 - 1)",
            func = function()
                -- bn(0,0,0,1) = 2^96; subtract 1 → x=-1, y=-1, z=-1, w=0
                local r = bn(0, 0, 0, 1) - BN(1)
                Should(r.x):Be(-1)
                Should(r.y):Be(-1)
                Should(r.z):Be(-1)
                Should(r.w):Be(0)
                Should( tostring(r) ):Be("79228162514264337593543950335")
            end
        },

        -- ────────────────────────────────────────────────────────────────
        -- __mul  (multiplication)
        -- ────────────────────────────────────────────────────────────────

        {
            name = "mul: simple 6 * 7 = 42",
            func = function()
                local r = BN(6) * BN(7)
                Should(r.x):Be(42)
                Should(r.y):Be(0)
                Should(r.z):Be(0)
                Should(r.w):Be(0)
            end
        },
        {
            name = "mul: 100000 * 100000 = 10000000000 (crosses 32-bit)",
            func = function()
                -- 10^10 = 0x2_540B_E400; x = 0x540BE400 = 1410065408, y = 2
                local r = BN(100000) * BN(100000)
                Should( tostring(r) ):Be("10000000000")
                Should(r.y):Be(2)
                Should(r.x):Be(1410065408)
            end
        },
        {
            name = "mul: 2^32 * 2^32 = 2^64 (result in z word)",
            func = function()
                -- bn(0,1) = 2^32; (2^32)^2 = 2^64 → z=1
                local r = bn(0, 1) * bn(0, 1)
                Should(r.x):Be(0)
                Should(r.y):Be(0)
                Should(r.z):Be(1)
                Should(r.w):Be(0)
            end
        },
        {
            name = "mul: (2^32-1)^2 = 2^64 - 2^33 + 1",
            func = function()
                -- (0xFFFFFFFF)^2 = 0xFFFFFFFE_00000001
                -- x = 1, y = -2 (0xFFFFFFFE as signed int32)
                local r = bn(-1) * bn(-1)
                Should(r.x):Be(1)
                Should(r.y):Be(-2)  -- 0xFFFFFFFE
                Should(r.z):Be(0)
                Should(r.w):Be(0)
                Should( tostring(r) ):Be("18446744065119617025")
            end
        },
        {
            name = "mul: 2^48 * 2^48 = 2^96 (result in w word)",
            func = function()
                -- 2^48 = bn(0, 0x10000) since 2^48 = 2^32 * 2^16
                -- (2^48)^2 = 2^96 → w=1
                local r = bn(0, 0x10000) * bn(0, 0x10000)
                Should(r.x):Be(0)
                Should(r.y):Be(0)
                Should(r.z):Be(0)
                Should(r.w):Be(1)
            end
        },
        {
            name = "mul: 2^64 * 2^64 truncates to zero (overflows 128 bits)",
            func = function()
                -- bn(0,0,1) * bn(0,0,1) = 2^128, which exceeds 128 bits → 0
                local r = bn(0, 0, 1) * bn(0, 0, 1)
                Should(r.x):Be(0)
                Should(r.y):Be(0)
                Should(r.z):Be(0)
                Should(r.w):Be(0)
            end
        },
        {
            name = "mul: multiply by zero gives zero",
            func = function()
                local r = BN(123456789) * BN(0)
                Should(r.x):Be(0)
                Should(r.y):Be(0)
                Should(r.z):Be(0)
                Should(r.w):Be(0)
            end
        },
        {
            name = "mul: multiply by one is identity",
            func = function()
                local r = bn(0xDEAD, 0xBEEF) * BN(1)
                Should(r.x):Be(0xDEAD)
                Should(r.y):Be(0xBEEF)
                Should(r.z):Be(0)
                Should(r.w):Be(0)
            end
        },

        -- ────────────────────────────────────────────────────────────────
        -- Max signed 128-bit value: 2^127 - 1
        -- w=0x7FFFFFFF (2147483647), z=y=x=0xFFFFFFFF (-1 as signed int32)
        -- ────────────────────────────────────────────────────────────────

        {
            name = "max signed 128-bit: direct construction tostring",
            func = function()
                -- 2^127 - 1 = 170141183460469231731687303715884105727
                local r = bn(-1, -1, -1, 2147483647)
                Should( tostring(r) ):Be("170141183460469231731687303715884105727")
            end
        },
        {
            name = "max signed 128-bit: reached via (1 << 127) - 1",
            func = function()
                local r = bn(1):__shl(127) - BN(1)
                Should(r.x):Be(-1)          -- 0xFFFFFFFF
                Should(r.y):Be(-1)          -- 0xFFFFFFFF
                Should(r.z):Be(-1)          -- 0xFFFFFFFF
                Should(r.w):Be(2147483647)  -- 0x7FFFFFFF
                Should( tostring(r) ):Be("170141183460469231731687303715884105727")
            end
        },
        {
            name = "max signed 128-bit + 1 = 2^127 (w flips to 0x80000000)",
            func = function()
                local max = bn(-1, -1, -1, 2147483647)
                local r = max + BN(1)
                Should(r.x):Be(0)
                Should(r.y):Be(0)
                Should(r.z):Be(0)
                Should(r.w):Be(-2147483648)  -- 0x80000000, i.e. 2^127
            end
        },

        -- ────────────────────────────────────────────────────────────────
        -- __div  (integer division)
        -- ────────────────────────────────────────────────────────────────

        {
            name = "div: 100 / 7 = 14",
            func = function()
                Should( tostring( BN(100) / BN(7) ) ):Be("14")
            end
        },
        {
            name = "div: negative dividend (-100 / 7 = -14)",
            func = function()
                Should( tostring( BN(-100) / BN(7) ) ):Be("-14")
            end
        },
        {
            name = "div: negative divisor (100 / -7 = -14)",
            func = function()
                Should( tostring( BN(100) / BN(-7) ) ):Be("-14")
            end
        },
        {
            name = "div: both negative (-100 / -7 = 14)",
            func = function()
                Should( tostring( BN(-100) / BN(-7) ) ):Be("14")
            end
        },
        {
            name = "div: large number (2^64 / 2^32 = 2^32)",
            func = function()
                Should( tostring( bn(0, 0, 1) / bn(0, 1) ) ):Be("4294967296")
            end
        },
    }
}
