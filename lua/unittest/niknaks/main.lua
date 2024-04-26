-- Unit tests for the bitbuffer module
return {
    groupname = "Main",
    init = function()
        Should(_UNITTEST)
            :WithMessage("Unit test flag not set")
            .And:BeTrue()

        require("niknaks")

        Should(NikNaks):Exist()
            .And:BeOfType("table")
    end,
    cases = {
        {
            name = "Load AutoInclude",
            func = function()
                Should(NikNaks.AutoInclude):Exist()
                    .And:BeOfType("function")
            end
        },
        {
            name = "Load AutoIncludeFolder",
            func = function()
                Should(NikNaks.AutoIncludeFolder):Exist()
                    .And:BeOfType("function")
            end
        },
    }
}