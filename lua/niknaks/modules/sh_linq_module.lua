
---@class LINQ
local t = {}
t.__index = t
t.MetaName = "LINQ"
NikNaks.__metatables["LINQ"] = t

---Creates a new LINQ object.
---
---**Note**: Table needs to be an array.
---@generic T: any
---@param tbl T[]
---@return LINQ
function NikNaks.LINQ(tbl)
    local self = setmetatable({}, t)
    ---@diagnostic disable-next-line: invisible
    self.tbl = tbl
    return self
end

---Returns as a string
---@return string
function t:ToString()
    return "LINQ[" .. self:Count() .. "]"
end

--#region Filters

---Filters the table based on the given predicate
---@param predicate function
---@return self
function t:Where(predicate)
    local tbl = {}
    for k, v in pairs(self.tbl) do
        if predicate(v, k) then
            table.insert(tbl, v)
        end
    end
    self.tbl = tbl
    return self
end

---Projects the table based on the given selector
---@param selector function
---@return self
function t:Select(selector)
    local tbl = {}
    for k, v in pairs(self.tbl) do
        local a, b, c, d, e, f = selector(v, k)
        if b == nil then
            table.insert(tbl, a)
        else
            table.insert(tbl, {a, b, c, d, e, f})
        end
    end
    self.tbl = tbl
    return self
end

---Projects the table based on the given selector. Flattens the result (Each element in the result is a separate element in the table)
---@param selector function
---@return self
function t:SelectMany(selector)
    local tbl = {}
    for k, v in pairs(self.tbl) do
        for _, value in ipairs({selector(v, k)}) do
            table.insert(tbl, value)
        end
    end
    self.tbl = tbl
    return self
end

---Filters the table based on the given type.
---
---**Warning:** This function is slow and should be used sparingly.
---@param strType string
---@return self
function t:OfType(strType)
    local tbl = {}
    for _, v in pairs(self.tbl) do
        if strType == type(v) then
            table.insert(tbl, v)
        end
    end
    self.tbl = tbl
    return self
end

---Filters the table based on the given types.
---
---**Warning:** This function is slow and should be used sparingly.
---@param types table<string>
---@return self
function t:OfTypes(types)
    local tbl = {}
    for _, v in pairs(self.tbl) do
        if table.HasValue(types, type(v)) then
            table.insert(tbl, v)
        end
    end
    self.tbl = tbl
    return self
end

--#endregion

--#region Variables

---Returns the first element that satisfies the predicate
---@param predicate function
---@return any
function t:Single(predicate)
    for k, v in pairs(self.tbl) do
        if predicate(v, k) then
            return v
        end
    end
    return nil
end

---Returns the first element that satisfies the predicate or the default value
---@param predicate function
---@param default any
---@return any
function t:SingleOrDefault(predicate, default)
    for k, v in pairs(self.tbl) do
        if predicate(v, k) then
            return v
        end
    end
    return default
end

---Returns true if any element in the table satisfies the predicate
---@param predicate any
---@return boolean
function t:Any(predicate)
    for k, v in pairs(self.tbl) do
        if predicate(v, k) then
            return true
        end
    end
    return false
end

---Returns true if all elements in the table satisfy the predicate
---@param predicate any
---@return boolean
function t:All(predicate)
    for k, v in pairs(self.tbl) do
        if not predicate(v, k) then
            return false
        end
    end
    return true
end

---Returns the number of elements in the table
---@return number
function t:Count()
    return #self.tbl
end

---Returns true if the table is empty
---@return boolean
function t:Empty()
    return #self.tbl == 0
end

---Returns the sum of the elements in the table
---@return number
---
---**Warning:** This function only works with numbers.
function t:Sum()
    local sum = 0
    for k, v in pairs(self.tbl) do
        sum = sum + v
    end
    return sum
end

---Returns the average of the elements in the table
---@return number
---
---**Warning:** This function only works with numbers.
function t:Average()
    return self:Sum() / self:Count()
end

---Returns the minimum element in the table
---@return any
function t:Min()
    local min = self.tbl[1]
    for k, v in pairs(self.tbl) do
        if v < min then
            min = v
        end
    end
    return min
end

---Returns the maximum element in the table
---@return any
function t:Max()
    local max = self.tbl[1]
    for k, v in pairs(self.tbl) do
        if v > max then
            max = v
        end
    end
    return max
end

---Returns true if the table contains the element
---@param element any
---@return boolean
function t:Contains(element)
    for k, v in pairs(self.tbl) do
        if v == element then
            return true
        end
    end
    return false
end

---First element of the table
---@return any
function t:First()
    return self.tbl[1]
end

---First element of the table or the default value
---@param default any
---@return any
function t:FirstOrDefault(default)
    local val = self.tbl[1]
    return val == nil and default or val
end

---Last element of the table
---@return any
function t:Last()
    return self.tbl[#self.tbl]
end

---Last element of the table or the default value
---@param default any
---@return any
function t:LastOrDefault(default)
    local val = self.tbl[#self.tbl]
    return val == nil and default or val
end

---Element at the given index
---@param index number
---@return any
function t:ElementAt(index)
    return self.tbl[index]
end

---Element at the given index or the default value
---@param index number
---@param default any
---@return any
function t:ElementAtOrDefault(index, default)
    local val = self.tbl[index]
    return val == nil and default or val
end

---Returns as a table
---@return any[]
function t:ToTable()
    return self.tbl
end

--#endregion

--#region Modifiers

---Splits it into chunks of the given size
---@param size number
---@return any[]
function t:Chunk(size)
    ---@type LINQ[]
    local result = {}
    local chunk = {}
    local num = #self.tbl
    for i = 1, num do
        table.insert(chunk, self.tbl[i])
        if i % size == 0 or i == num then
            table.insert(result, chunk)
            chunk = {}
        end
    end
    return result
end

---Orders the table based on the given comparer
---@param comparer function?
---@return self
function t:OrderBy(comparer)
    table.sort(self.tbl, comparer)
    return self
end

---Reverses the table
---@return self
function t:Reverse()
    local tbl = {}
    for i = #self.tbl, 1, -1 do
        table.insert(tbl, self.tbl[i])
    end
    self.tbl = tbl
    return self
end

---Distincts the table
---@return self
function t:Distinct()
    local tbl = {}
    for k, v in pairs(self.tbl) do
        if not table.HasValue(tbl, v) then
            table.insert(tbl, v)
        end
    end
    self.tbl = tbl
    return self
end

---Unions the table with the given table
---@param tbl LINQ
---@return self
function t:Union(tbl)
    for _, v in pairs(tbl.tbl) do
        if not table.HasValue(self.tbl, v) then
            table.insert(self.tbl, v)
        end
    end
    return self
end

---Intersects the table with the given table
---@param tbl LINQ
---@return self
function t:Intersect(tbl)
    local newTbl = {}
    for _, v in pairs(self.tbl) do
        if table.HasValue(tbl.tbl, v) then
            table.insert(newTbl, v)
        end
    end
    self.tbl = newTbl
    return self
end

---Zips the table with the given table
---@param tbl LINQ
---@param func function<any, any> # Returns the new value based on the two values.
---@return self
function t:Zip(tbl, func)
    local newTbl = {}
    for i = 1, math.min(#self.tbl, #tbl.tbl) do
        table.insert(newTbl, func(self.tbl[i], tbl.tbl[i]))
    end
    self.tbl = newTbl
    return self
end

---Groups the table based on the given keySelector
---@param keySelector function<string> # The key selector.
---@return self
function t:GroupBy(keySelector)
    local tbl = {}
    for k, v in pairs(self.tbl) do
        local key = keySelector(v, k)
        if not tbl[key] then
            tbl[key] = {}
        end
        table.insert(tbl[key], v)
    end
    self.tbl = tbl
    return self
end

---Skips the first n elements
---@param n number
---@return self
function t:Skip(n)
    local tbl = {}
    for i = n + 1, #self.tbl do
        table.insert(tbl, self.tbl[i])
    end
    self.tbl = tbl
    return self
end

---Skips the last n elements
---@param n number
---@return self
function t:SkipLast(n)
    local tbl = {}
    for i = 1, #self.tbl - n do
        table.insert(tbl, self.tbl[i])
    end
    self.tbl = tbl
    return self
end

---Skips elements from the beginning until the predicate is false
---@param predicate function
---@return self
function t:SkipWhile(predicate)
    local tbl = {}
    local skip = true
    for k, v in pairs(self.tbl) do
        if skip and not predicate(v, k) then
            skip = false
        end
        if not skip then
            table.insert(tbl, v)
        end
    end
    self.tbl = tbl
    return self
end

---Takes the first n elements
---@param n number
---@return self
function t:Take(n)
    local tbl = {}
    for i = 1, n do
        table.insert(tbl, self.tbl[i])
    end
    self.tbl = tbl
    return self
end

---Takes the last n elements
---@param n number
---@return self
function t:TakeLast(n)
    local tbl = {}
    for i = #self.tbl - n + 1, #self.tbl do
        table.insert(tbl, self.tbl[i])
    end
    self.tbl = tbl
    return self
end

---Takes elements from the beginning until the predicate is false
---@param predicate function
---@return self
function t:TakeWhile(predicate)
    local tbl = {}
    for k, v in pairs(self.tbl) do
        if not predicate(v, k) then
            break
        end
        table.insert(tbl, v)
    end
    self.tbl = tbl
    return self
end

--#endregion
