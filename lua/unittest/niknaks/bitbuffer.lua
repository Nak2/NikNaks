-- Unit tests for the bitbuffer module
return {
    groupname = "BitBuffer",
    init = function()
        Should(_UNITTEST)
            :WithMessage("Unit test flag not set")
            .And:BeTrue()

        require("niknaks")

        Should(NikNaks.BitBuffer):Exist()
            .And:BeOfType("table")
    end,
    cases = {
        {
            name = "Write / Read",
            func = function()
                local bb = NikNaks.BitBuffer()
                bb:Write("n")
                    :Write("ik")
                    :Write("skan")
                    :Seek(0)
                Should(bb:Read()):Be("niknaks")
            end
        },
        {
            name = "WriteRawData / ReadRawData",
            func = function()
                local bb = NikNaks.BitBuffer.Create();
                bb:SetLittleEndian()
                bb:WriteRawData("niknaks")
                bb:SetBigEndian()
                bb:Seek(0)

                Should(bb:ReadRawData(7)):Be("niknaks")
            end
        },
        {
            name = "Seek",
            func = function()
                local bb = NikNaks.BitBuffer()
                bb:WriteRawData("NikNaks World")
                    :Seek(0)
                Should(bb:ReadRawData(6)):Be("NikNak")
            end
        },
        {
            name = "Skip",
            func = function()
                local bb = NikNaks.BitBuffer()
                bb:WriteRawData("NikNaks World")
                    :Seek(0)
                    :Skip(6 * 8)
                Should(bb:ReadRawData(6)):Be("s Worl")
            end
        },
        {
            name = "Tell",
            func = function()
                local bb = NikNaks.BitBuffer()
                bb:Write("NikNaks World")
                    :Seek(0)
                Should(bb:Tell()):Be(0)
                bb:Read(5)
                Should(bb:Tell()):Be(5 * 8)
            end
        },
        {
            name = "Size",
            func = function()
                local bb = NikNaks.BitBuffer()
                bb:Write("NikNaks World")
                Should(bb:Size()):Be(13 * 8)
            end
        },
        {
            name = "EndOfData",
            func = function()
                local bb = NikNaks.BitBuffer() --[[@as BitBuffer]]
                bb:Write("NikNaks World")
                    :Seek(0)
                Should(bb:EndOfData()):Be(false)
                bb:Read(12 * 8)
                Should(bb:EndOfData()):Be(true)
            end
        },
        {
            name = "UInt",
            func = function()
                local bb = NikNaks.BitBuffer()
                bb:WriteUInt(0x12345678, 32)
                    :WriteUInt(0x123, 15)
                    :WriteUInt(0x123, 17)
                    :WriteUInt(0x1, 3)
                    :Seek(0)
                Should(bb:ReadUInt(32)):Be(0x12345678)
                Should(bb:ReadUInt(15)):Be(0x123)
                Should(bb:ReadUInt(17)):Be(0x123)
                Should(bb:ReadUInt(3)):Be(0x1)
            end
        },
        {
            name = "Int",
            func = function()
                local bb = NikNaks.BitBuffer()
                bb:WriteInt(-12345678, 32)
                    :WriteInt(-0x123, 15)
                    :WriteInt(0x123, 17)
                    :WriteInt(-0x1, 3)
                    :Seek(0)
                Should(bb:ReadInt(32)):Be(-12345678)
                Should(bb:ReadInt(15)):Be(-0x123)
                Should(bb:ReadInt(17)):Be(0x123)
                Should(bb:ReadInt(3)):Be(-0x1)
            end
        },
        {
            name = "SetBigEndian / SetLittleEndian",
            func = function()
                local bb = NikNaks.BitBuffer()
                bb:SetBigEndian()
                bb:WriteInt(0x12345678, 32)
                bb:SetLittleEndian()
                bb:WriteInt(0x12345678, 32)
                bb:Seek(0)
                Should(bb:ReadInt(32)):Be(0x78563412)
                Should(bb:ReadInt(32)):Be(0x12345678)
            end
        },
        {
            name = "Snort",
            func = function()
                local bb = NikNaks.BitBuffer() --[[@as BitBuffer]]
                bb:WriteSnort(2)
                    :Seek(0)
                Should(bb:ReadSnort()):Be(2)
            end
        },
        {
            name = "Nibble",
            func = function()
                local bb = NikNaks.BitBuffer() --[[@as BitBuffer]]
                bb:WriteNibble(12)
                    :Seek(0)
                Should(bb:ReadNibble()):Be(12)
            end
        },
        {
            name = "Byte",
            func = function()
                local bb = NikNaks.BitBuffer()
                bb:WriteByte(0x12)
                    :Seek(0)
                Should(bb:ReadByte()):Be(0x12)
            end
        },
        {
            name = "Signed Byte",
            func = function()
                local bb = NikNaks.BitBuffer() --[[ @as BitBuffer ]]
                bb:WriteSignedByte(-127)
                    :Seek(0)
                Should(bb:ReadSignedByte()):Be(-127)
            end
        },
        {
            name = "Short",
            func = function()
                local bb = NikNaks.BitBuffer()
                bb:WriteShort(0x1234)
                    :Seek(0)
                Should(bb:ReadShort()):Be(0x1234)
            end
        },
        {
            name = "UShort",
            func = function()
                local bb = NikNaks.BitBuffer()
                bb:WriteUShort(0x1234)
                    :Seek(0)
                Should(bb:ReadUShort()):Be(0x1234)
            end
        },
        {
            name = "Long",
            func = function()
                local bb = NikNaks.BitBuffer()
                bb:WriteLong(0x12345678)
                    :Seek(0)
                Should(bb:ReadLong()):Be(0x12345678)
            end
        },
        {
            name = "ULong",
            func = function()
                local bb = NikNaks.BitBuffer()
                bb:WriteULong(0x12345678)
                    :Seek(0)
                Should(bb:ReadULong()):Be(0x12345678)
            end
        },
        {
            name = "Float",
            func = function()
                local bb = NikNaks.BitBuffer()
                bb:WriteFloat(123.456)
                bb:WriteFloat(1)
                bb:WriteFloat(2)
                bb:WriteFloat(0 * -1)
                    :Seek(0)

                Should(math.Round(bb:ReadFloat(), 3)):Be(123.456)
                Should(bb:ReadFloat()):Be(1)
                Should(bb:ReadFloat()):Be(2)
                Should(1 / bb:ReadFloat())
                    :WithMessage("Expected negative 0")
                    .And:Be(-math.huge)
            end
        },
        {
            name = "Double",
            func = function()
                local max_double = 1.7976931348623157e+306
                -- 01111111 10000100 01111010 11100001 01000111 10101110 00010100 01111010
                local max_double_bytes = { 0x7F, 0x84, 0x7A, 0xE1, 0x47, 0xAE, 0x14, 0x7A }

                local bb = NikNaks.BitBuffer()
                bb:SetBigEndian()
                bb:WriteDouble(max_double)
                for i = 1, 8 do
                    bb:WriteByte(max_double_bytes[i])
                end
                bb:WriteDouble(123.456)
                bb:WriteDouble(1)
                bb:WriteDouble(2)
                bb:WriteDouble(0 * -1)
                bb:WriteDouble(max_double)
                bb:WriteDouble(-max_double)
                
                bb:Seek(0)

                -- Make sure double match max_double in bytes                
                for i = 1, 8 do
                    local rb = bb:ReadByte()
                    Should(rb):WithMessage("Byte " .. i .. " is " .. rb .. " but should be " .. max_double_bytes[i])
                        .And:Be(max_double_bytes[i])
                end
                Should(math.abs(bb:ReadDouble() - max_double))
                    :WithMessage("Double encoding is not equal to max_double")
                    .And:BeLessThan(1e-14)

                Should(math.Round(bb:ReadDouble(), 3)):Be(123.456)
                Should(bb:ReadDouble()):Be(1)
                Should(bb:ReadDouble()):Be(2)
                Should(1 / bb:ReadDouble())
                    :WithMessage("Expected negative 0")
                    .And:Be(-math.huge)

                Should(math.abs(bb:ReadDouble() - max_double))
                    :BeLessThan(1e-14)

                Should(math.abs(bb:ReadDouble() + max_double))
                    :BeLessThan(1e-14)
            end
        },
        {
            name = "Boolean",
            func = function()
                local bb = NikNaks.BitBuffer()
                bb:WriteBoolean(true)
                    :Seek(0)
                Should(bb:ReadBoolean()):Be(true)
            end
        },
        {
            name = "String",
            func = function()
                local bb = NikNaks.BitBuffer() --[[@as BitBuffer]]
                bb:WriteString("Hello, World!")
                    :Seek(0)
                Should(bb:ReadString()):Be("Hello, World!")
            end
        },
        {
            name = "StringNull",
            func = function()
                local bb = NikNaks.BitBuffer() --[[@as BitBuffer]]
                bb:WriteStringNull("Hello, World!")
                    :Write("This is longer than the previous string")
                    :Seek(0)
                Should(bb:ReadStringNull(256)):Be("Hello, World!")
            end
        },
        {
            name = "Angle",
            func = function()
                local bb = NikNaks.BitBuffer()
                bb:WriteAngle(Angle(1, 2, 3))
                    :Seek(0)
                Should(bb:ReadAngle()):BeOfType("Angle")
                    .And:ContainKeys("p", "y", "r")
                    .And:Be(Angle(1, 2, 3))
            end
        },
        {
            name = "Vector",
            func = function()
                local bb = NikNaks.BitBuffer()
                bb:WriteVector(Vector(1, 2, 3))
                    :Seek(0)
                Should(bb:ReadVector()):BeOfType("Vector")
                    .And:ContainKeys("x", "y", "z")
                    .And:Be(Vector(1, 2, 3))
            end
        },
        {
            name = "Color",
            func = function()
                local bb = NikNaks.BitBuffer() --[[@as BitBuffer]]
                bb:WriteColor(Color(255, 0, 0, 255))
                    :Seek(0)
                Should(bb:ReadColor()):BeOfType("table")
                    .And:ContainKeys("r", "g", "b", "a")
                    .And:Be(Color(255, 0, 0, 255))
            end
        },
    }
}
