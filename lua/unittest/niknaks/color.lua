
return {
    groupname = "Color",
    init = function()
        Should(_UNITTEST)
            :WithMessage("Unit test flag not set")
            .And:BeTrue()

        require("niknaks")
    end,
    cases = {
        {
            name = "ColorToLuminance",
            func = function()
                Should(NikNaks.ColorToLuminance):Exist()
                    .And:BeOfType("function")

                Should(NikNaks.ColorToLuminance(Color(255, 255, 255)))
                    :Be(255)

                Should(NikNaks.ColorToLuminance(Color(0, 0, 0)))
                    :Be(0)

                Should(NikNaks.ColorToLuminance(Color(128, 128, 128)))
                    :Be(128)
            end
        },
        {
            name = "ColorToHex",
            func = function()
                Should(NikNaks.ColorToHex):Exist()
                    .And:BeOfType("function")

                Should(NikNaks.ColorToHex(Color(255, 255, 255)))
                    :Be("#FFFFFF")

                Should(NikNaks.ColorToHex(Color(0, 0, 0)))
                    :Be("#000000")

                Should(NikNaks.ColorToHex(Color(128, 128, 128)))
                    :Be("#808080")
            end
        },
        {
            name = "HexToColor",
            func = function()
                Should(NikNaks.HexToColor):Exist()
                    .And:BeOfType("function")

                Should(NikNaks.HexToColor("#FFFFFF"))
                    :Be(Color(255, 255, 255))

                Should(NikNaks.HexToColor("#000000"))
                    :Be(Color(0, 0, 0))

                Should(NikNaks.HexToColor("#808080"))
                    :Be(Color(128, 128, 128))
            end
        },
        {
            name = "ColorToCMYK",
            func = function()
                Should(NikNaks.ColorToCMYK):Exist()
                    .And:BeOfType("function")

                local c, m, y, k = NikNaks.ColorToCMYK(Color(255, 255, 255))
                Should(c):Be(0)
                Should(m):Be(0)
                Should(y):Be(0)
                Should(k):Be(0)

                local c, m, y, k = NikNaks.ColorToCMYK(Color(0, 0, 0))
                Should(c):Be(0)
                Should(m):Be(0)
                Should(y):Be(0)
                Should(k):Be(1)

                local c, m, y, k = NikNaks.ColorToCMYK(Color(128, 128, 128))
                Should(c):Be(0)
                Should(m):Be(0)
                Should(y):Be(0)
                Should(math.Round(k, 1)):Be(0.5)
            end
        },
        {
            name = "CMYKToColor",
            func = function()
                Should(NikNaks.CMYKToColor):Exist()
                    .And:BeOfType("function")

                Should(NikNaks.CMYKToColor(0, 0, 0, 0))
                    :Be(Color(255, 255, 255))

                Should(NikNaks.CMYKToColor(0, 0, 0, 1))
                    :Be(Color(0, 0, 0))

                Should(NikNaks.CMYKToColor(0, 0, 0, 0.5))
                    :Be(Color(128, 128, 128))

                Should(NikNaks.CMYKToColor(0.5, 0.5, 0.5, 0.5))
                    :Be(Color(64, 64, 64))

                Should(NikNaks.CMYKToColor(0.5, 0.5, 0.5, 0))
                    :Be(Color(128, 128, 128))
            end
        },
        {
            name = "Brighten / Darken",
            func = function()
                local col = Color(255,255,255)
                Should(col.IncreaseBrightness)
                    :Exist()
                    .And:BeOfType("function")

                Should(col:IncreaseBrightness(-50))
                    :BeOfType("table")
                    .And:Be(Color(205,205,205))

                Should(col:IncreaseBrightness(50))
                    :BeOfType("table")
                    .And:Be(Color(255,255,255))
            end
        },
        {
            name = "Invert",
            func = function()
                local col = Color(255,255,255)
                Should(col.Invert)
                    :Exist()
                    .And:BeOfType("function")

                Should(col:Invert())
                    :BeOfType("table")
                    .And:Be(Color(0,0,0))
            end
        },
        {
            name = "Grayscale",
            func = function()
                local col = Color(255,255,255)
                Should(col.ToGrayscale)
                    :Exist()
                    .And:BeOfType("function")

                Should(col:ToGrayscale())
                    :BeOfType("table")
                    .And:Be(Color(255,255,255))

                col.r = 0
                col.g = 0
                col.b = 0
                Should(col:ToGrayscale())
                    :BeOfType("table")
                    .And:Be(Color(0,0,0))

                col.r = 150
                col.g = 125
                col.b = 100

                Should(col:ToGrayscale())
                    :BeOfType("table")
                    .And:Be(Color(130,130,130))
            end
        },
        {
            name = "IsBright",
            func = function()
                local col = Color(255,255,255)
                Should(col.IsBright):Exist()
                    .And:BeOfType("function")

                Should(col:IsBright())
                    :BeTrue()

                col.b = 0
                col.g = 0

                Should(col:IsBright())
                    :BeFalse()

                col.r = 0
                col.g = 255

                Should(col:IsBright())
                    :BeTrue()

                col.g = 0

                Should(col:IsBright())
                    :BeFalse()
            end
        },
        {
            name = "ColorRGBExp32ToColor",
            func = function()
                Should(NikNaks.ColorRGBExp32ToColor):Exist()
                    .And:BeOfType("function")

                local struct = {
                    r = 0,
                    g = 127,
                    b = 255,
                    exponent = 0
                }
                Should(NikNaks.ColorRGBExp32ToColor(struct))
                    :Be(Color(0,93,128))

                struct.exponent = 1
                Should(NikNaks.ColorRGBExp32ToColor(struct))
                    :Be(Color(0,127,175))

                struct.exponent = 2
                struct.r = 255

                Should(NikNaks.ColorRGBExp32ToColor(struct))
                    :Be(Color(239,174,239))

                struct.r = 0
                struct.g = 0
                struct.b = 0

                Should(NikNaks.ColorRGBExp32ToColor(struct))
                    :Be(Color(0,0,0))

                struct.r = 255
                struct.g = 255
                struct.b = 255
                struct.exponent = 0

                Should(NikNaks.ColorRGBExp32ToColor(struct))
                    :Be(Color(128,128,128))

                struct.exponent = 3

                Should(NikNaks.ColorRGBExp32ToColor(struct))
                    :Be(Color(255,255,255))
            end
        },
    }
}