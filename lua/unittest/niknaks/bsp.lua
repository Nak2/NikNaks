return {
    groupname = "BSP [gm_construct.bsp]",
    init = function()
        Should(_UNITTEST)
            :WithMessage("Unit test flag not set")
            .And:BeTrue()

        require("niknaks")

        Should(NikNaks.Map):Exist()
            .And:BeOfType("function")

        _MAP = NikNaks.Map("gm_construct.bsp")

        Should(_MAP):Exist()
            .And:BeOfType("table")
    end,
    cases = {
        {
            name = "Version",
            func = function()
                Should(_MAP:GetVersion())
                    :Be(20)
            end
        },
        {
            name = "Lump",
            func = function()
                Should(_MAP:GetLump(63))
                    :BeOfType("table")
                    .And:WithMessage("Lump 64 should be empty")
                    .And:Pass(function(lump)
                        ---@cast lump BitBuffer
                        return lump:Size() == 0
                    end)

                Should(_MAP:GetGameLumpHeaders())
                    :WithMessage("Game lump headers do not match")
                    .And:BeOfType("table")
                    .And:HaveCount(3)

                Should(_MAP:GetGameLump(1936749168))
                    :WithMessage("Can't locate static prop lump")
                    .And:BeOfType("table")
            end
        },
        {
            name = "Entities",
            func = function()
                local mapEnt = Should(_MAP:GetEntities())
                    :BeOfType("table")
                    .And:HaveCount(1227)
                    .Result[0]

                Should(mapEnt):BeOfType("table")
                    .And:ContainKey("classname", "worldspawn")
                    .And:ContainKey("detailmaterial", "detail/detailsprites")

                Should(mapEnt.origin):BeOfType("Vector")
                    .And:Be(Vector(0, 0, 0))

                Should(mapEnt.angles):BeOfType("Angle")
                    .And:Be(Angle(0, 0, 0))
            end
        },
        {
            name = "Skybox",
            func = function()
                Should(_MAP:HasSkyBox())
                    :WithMessage("Skybox not found")
                    .And:BeTrue()

                Should(_MAP:GetSkyBoxScale())
                    :Be(16)

                local vec = Should(_MAP:GetSkyBoxPos())
                    :WithMessage("Skybox position is incorrect")
                    .And:ContainKey("x", -1428)
                    .And:ContainKey("y", 1645)
                    .And:Pass(function(vec)
                        return vec.z > 10991 and vec.z < 10992
                    end)

                local min, max = _MAP:GetSkyboxSize()
                Should(min):WithMessage("Skybox size is incorrect")
                    .And:Be(Vector(-15104, -15104, 10367))
                
                Should(max):WithMessage("Skybox size is incorrect")
                    .And:Be(Vector(15616, 15104, 15231))

                local TestVec = Vector(123,123,0)
                local SkyVec = _MAP:SkyBoxToWorld(TestVec)
                Should(SkyVec):WithMessage("Skybox to world conversion failed")
                    .And:BeOfType("Vector")
                    .And:ContainKey("x", 24816)

                Should(_MAP:WorldToSkyBox(SkyVec)):WithMessage("World to skybox conversion failed")
                    .And:Be(TestVec)
            end
        }
    }
}