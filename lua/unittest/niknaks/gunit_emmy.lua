
---@meta

---@class GUnit.UnitTest
---@field WithMessage fun(self: GUnit.UnitTest, message: string): GUnit.UnitResult # Overrides the failure message shown when this assertion fails.
---@field Exist fun(self: GUnit.UnitTest): GUnit.UnitResult # Asserts the value is non-nil and not false.
---@field NotExist fun(self: GUnit.UnitTest): GUnit.UnitResult # Asserts the value is nil or false.
---@field Be fun(self: GUnit.UnitTest, value: any): GUnit.UnitResult # Asserts deep equality between the tested value and the given value.
---@field BeOfType fun(self: GUnit.UnitTest, _type: string): GUnit.UnitResult # Asserts that type() of the value matches the given type string.
---@field BeTrue fun(self: GUnit.UnitTest): GUnit.UnitResult # Asserts the value is exactly true (not just truthy).
---@field BeFalse fun(self: GUnit.UnitTest): GUnit.UnitResult # Asserts the value is exactly false (not just falsy).
---@field BeNil fun(self: GUnit.UnitTest): GUnit.UnitResult # Asserts the value is nil.
---@field BeLessThan fun(self: GUnit.UnitTest, value: number): GUnit.UnitResult # Asserts the value is strictly less than the given number.
---@field BeLessThanOrEqual fun(self: GUnit.UnitTest, value: number): GUnit.UnitResult # Asserts the value is less than or equal to the given number.
---@field BeGreaterThan fun(self: GUnit.UnitTest, value: number): GUnit.UnitResult # Asserts the value is strictly greater than the given number.
---@field BeGreaterThanOrEqual fun(self: GUnit.UnitTest, value: number): GUnit.UnitResult # Asserts the value is greater than or equal to the given number.
---@field Contain fun(self: GUnit.UnitTest, ...: any): GUnit.UnitResult # Asserts the table contains all of the given values.
---@field ContainKey fun(self: GUnit.UnitTest, key: any, val: any?): GUnit.UnitResult # Asserts the table has the given key, optionally checking its value.
---@field ContainKeys fun(self: GUnit.UnitTest, ...: any): GUnit.UnitResult # Asserts the table contains all of the specified keys.
---@field BeEmpty fun(self: GUnit.UnitTest): GUnit.UnitResult # Asserts the table or string has no elements.
---@field NotBeEmpty fun(self: GUnit.UnitTest): GUnit.UnitResult # Asserts the table or string has at least one element.
---@field BeUniqueItems fun(self: GUnit.UnitTest): GUnit.UnitResult # Asserts every item in the table appears exactly once.
---@field BeOrdered fun(self: GUnit.UnitTest): GUnit.UnitResult # Asserts the table is sorted in ascending order.
---@field BeIn fun(self: GUnit.UnitTest, tbl: table): GUnit.UnitResult # Asserts the value exists as an element within the given table.
---@field BeNotIn fun(self: GUnit.UnitTest, tbl: table): GUnit.UnitResult # Asserts the value does not exist as an element within the given table.
---@field BeSameItems fun(self: GUnit.UnitTest): GUnit.UnitResult # Asserts all elements in the table are equal to each other.
---@field HaveCount fun(self: GUnit.UnitTest, count: number): GUnit.UnitResult # Asserts the table or string has exactly the given number of elements.
---@field Pass fun(self: GUnit.UnitTest, predicate: fun(value: any): boolean): GUnit.UnitResult # Asserts the value satisfies a custom predicate function.
---@field BeString fun(self: GUnit.UnitTest): GUnit.UnitResult # Asserts the value is of type string.
---@field StartWith fun(self: GUnit.UnitTest, value: string): GUnit.UnitResult # Asserts the string begins with the given prefix.
---@field EndWith fun(self: GUnit.UnitTest, value: string): GUnit.UnitResult # Asserts the string ends with the given suffix.
---@field ContainString fun(self: GUnit.UnitTest, value: string): GUnit.UnitResult # Asserts the string contains the given substring.
---@field Result any # The raw value being tested.

---@class GUnit.UnitResult
---@field And GUnit.UnitTest # Chains back to the UnitTest to allow further assertions on the same value.
---@field Result any # The raw value being tested.

if false then
    --- Creates a new assertion context for the given value.
    ---@param value any # The value to test.
    ---@return GUnit.UnitTest
    function Should(value) end

    _UNITTEST = true
end
