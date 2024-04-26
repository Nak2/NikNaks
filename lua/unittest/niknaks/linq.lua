
return {
    groupname = "LINQ",
    init = function()
        Should(_UNITTEST)
            :WithMessage("Unit test flag not set")
            .And:BeTrue()

        require("niknaks")
        Should(NikNaks.LINQ):Exist()
            .And:BeOfType("function")
    end,
    cases = {
        {
            name = "Select",
            func = function()
                local linq = NikNaks.LINQ({1, 2, 3, 4, 5})
                local result = linq
                    :Select(function(v) return v * 2 end)
                    :ToTable()

                Should(result):Be({2, 4, 6, 8, 10})
            end
        },
        {
            name = "Where",
            func = function()
                local linq = NikNaks.LINQ({1, 2, 3, 4, 5})
                local result = linq
                    :Where(function(v) return v % 2 == 0 end)
                    :ToTable()

                Should(result):Be({2, 4})
            end
        },
        {
            name = "OrderBy",
            func = function()
                local linq = NikNaks.LINQ({5, 4, 3, 2, 1})
                local result = linq
                    :OrderBy()
                    :ToTable()

                Should(result):Be({1, 2, 3, 4, 5})
            end
        },
        {
            name = "GroupBy",
            func = function()
                local linq = NikNaks.LINQ({1, 2, 3, 4, 5})
                local result = linq
                    :GroupBy(function(v) return v % 2 end)
                    :ToTable()

                Should(result):BeOfType("table")
                    .And:Be({
                        [0] = {2, 4},
                        [1] = {1, 3, 5}
                    })
            end
        },
        {
            name = "Chunk",
            func = function()
                local linq = NikNaks.LINQ({1, 2, 3, 4, 5})
                local result = linq
                    :Chunk(2)

                Should(result):Be({
                    {1, 2},
                    {3, 4},
                    {5}
                })
            end
        },
        {
            name = "Reverse",
            func = function()
                local linq = NikNaks.LINQ({1, 2, 3, 4, 5})
                local result = linq
                    :Reverse()
                    :ToTable()

                Should(result):BeOfType("table")
                    .And:Be({5, 4, 3, 2, 1})
            end
        },
        {
            name = "Skip",
            func = function()
                local linq = NikNaks.LINQ({1, 2, 3, 4, 5})
                local result = linq
                    :Skip(2)
                    :ToTable()

                Should(result):Be({3, 4, 5})
            end
        },
        {
            name = "Take",
            func = function()
                local linq = NikNaks.LINQ({1, 2, 3, 4, 5})
                local result = linq
                    :Take(2)
                    :ToTable()

                Should(result):Be({1, 2})

                result = NikNaks.LINQ({1,2,3,4,5,6})
                    :Take(5)
                    :Take(3)
                    :ToTable()

                Should(result):Be({1, 2, 3})
            end
        },
        {
            name = "First",
            func = function()
                local linq = NikNaks.LINQ({1, 2, 3, 4, 5})
                local result = linq
                    :First()

                Should(result):Be(1)
            end
        },
        {
            name = "Last",
            func = function()
                local linq = NikNaks.LINQ({1, 2, 3, 4, 5})
                local result = linq
                    :Last()

                Should(result):Be(5)
            end
        },
        {
            name = "Count",
            func = function()
                local linq = NikNaks.LINQ({1, 2, 4, 5})
                local result = linq
                    :Count()

                Should(result):Be(4)
            end
        },
        {
            name = "Any",
            func = function()
                local linq = NikNaks.LINQ({1, 2, 3, 4, 5})
                local result = linq
                    :Any(function(v) return v == 3 end)
                Should(result):BeTrue()

                result = linq
                    :Any(function(v) return v == 6 end)
                Should(result):BeFalse()
            end
        },
        {
            name = "All",
            func = function()
                local linq = NikNaks.LINQ({1, 2, 3, 4, 5})
                local result = linq
                    :All(function(v) return v > 0 end)

                Should(result):BeTrue()

                result = linq
                    :All(function(v) return v > 1 end)

                Should(result):BeFalse()
            end
        },
        {
            name = "Empty",
            func = function()
                local linq = NikNaks.LINQ({})
                local result = linq
                    :Empty()

                Should(result):BeTrue()

                linq = NikNaks.LINQ({1, 2, 3, 4, 5})
                result = linq
                    :Empty()

                Should(result):BeFalse()
            end
        },
        {
            name = "FirstOrDefault",
            func = function()
                local linq = NikNaks.LINQ({})
                local result = linq
                    :FirstOrDefault(0)

                Should(result):Be(0)

                linq = NikNaks.LINQ({1, 2, 3, 4, 5})
                result = linq
                    :FirstOrDefault(0)

                Should(result):Be(1)
            end
        },
        {
            name = "SingleOrDefault",
            func = function()
                local linq = NikNaks.LINQ({})
                local result = linq
                    :SingleOrDefault(function(v) return v == 3 end, 0)

                Should(result):Be(0)

                linq = NikNaks.LINQ({1, 2, 3, 4, 5})
                result = linq
                    :SingleOrDefault(function(v) return v == 3 end, 0)

                Should(result):Be(3)

                result = linq
                    :SingleOrDefault(function(v) return v == 6 end, 0)

                Should(result):Be(0)
            end
        },
        {
            name = "ElementAt",
            func = function()
                local linq = NikNaks.LINQ({1, 2, 3, 4, 5})
                local result = linq
                    :ElementAt(3)

                Should(result):Be(3)
            end
        },
        {
            name = "ElementAtOrDefault",
            func = function()
                local linq = NikNaks.LINQ({})
                local result = linq
                    :ElementAtOrDefault(2, 0)

                Should(result):Be(0)

                linq = NikNaks.LINQ({1, 2, 3, 4, 5})
                result = linq
                    :ElementAtOrDefault(3, 0)

                Should(result):Be(3)
            end
        },
        {
            name = "Contains",
            func = function()
                local linq = NikNaks.LINQ({1, 2, 3, 4, 5})
                local result = linq
                    :Contains(3)

                Should(result):BeTrue()

                result = linq
                    :Contains(6)

                Should(result):BeFalse()
            end
        },
        {
            name = "Distinct",
            func = function()
                local linq = NikNaks.LINQ({1, 2, 2, 3, 4, 5, 5})
                local result = linq
                    :Distinct()
                    :ToTable()

                Should(result):Be({1, 2, 3, 4, 5})
            end
        },
        {
            name = "Union",
            func = function()
                local linq1 = NikNaks.LINQ({1, 2, 3})
                local linq2 = NikNaks.LINQ({3, 4, 5})
                local result = linq1
                    :Union(linq2)
                    :ToTable()

                Should(result):Contain(1, 2, 3, 4, 5)
                    .And:HaveCount(5)
            end
        },
        {
            name = "Intersect",
            func = function()
                local linq1 = NikNaks.LINQ({1, 2, 3})
                local linq2 = NikNaks.LINQ({3, 4, 5})
                local result = linq1
                    :Intersect(linq2)
                    :ToTable()

                Should(result):Be({3})
            end
        },
        {
            name = "Zip",
            func = function()
                local linq1 = NikNaks.LINQ({1, 2, 3})
                local linq2 = NikNaks.LINQ({3, 4, 5})
                local result = linq1
                    :Zip(linq2, function(v1, v2) return v1 + v2 end)
                    :ToTable()

                Should(result):Be({4, 6, 8})
            end
        },
        {
            name = "Sum",
            func = function()
                local linq = NikNaks.LINQ({1, 2, 3, 4, 5})
                local result = linq
                    :Sum()

                Should(result):Be(15)
            end
        },
        {
            name = "Min",
            func = function()
                local linq = NikNaks.LINQ({1, 2, 3, 4, 5})
                local result = linq
                    :Min()

                Should(result):Be(1)
            end
        },
        {
            name = "Max",
            func = function()
                local linq = NikNaks.LINQ({1, 2, 3, 4, 5})
                local result = linq
                    :Max()

                Should(result):Be(5)
            end
        },
        {
            name = "Average",
            func = function()
                local linq = NikNaks.LINQ({1, 2, 3, 4, 5})
                local result = linq
                    :Average()

                Should(result):Be(3)
            end
        }
    }
}