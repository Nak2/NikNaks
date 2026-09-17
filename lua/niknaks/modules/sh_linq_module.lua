
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

--- Keeps only elements for which the predicate returns true.
---@param predicate fun(v: any, ...): boolean
---@param ... any Extra arguments forwarded to the predicate function.
---@return self
function t:Where(predicate, ...)
    local tbl = {}
    for _, v in pairs(self.tbl) do
        if predicate(v, ...) then
            tbl[#tbl + 1] = v
        end
    end
    self.tbl = tbl
    return self
end

--- Transforms each element using the selector. If the selector returns multiple values they are wrapped in a table.
---
--- Extra arguments after `selector` are forwarded to it on every call
---@param selector fun(v: any, ...): any
---@param ... any Extra arguments forwarded to the selector function.
---@return self
function t:Select(selector, ...)
    local tbl = {}
    for _, v in pairs(self.tbl) do
        local a, b, c, d, e, f = selector(v, ...)
        if b == nil then
            tbl[#tbl + 1] = a
        else
            tbl[#tbl + 1] = {a, b, c, d, e, f}
        end
    end
    self.tbl = tbl
    return self
end

--- Transforms each element and flattens the results into a single sequence.
---@param selector fun(v: any, k: any): any
---@return self
function t:SelectMany(selector)
    local tbl = {}
    for k, v in pairs(self.tbl) do
        for _, value in ipairs({selector(v, k)}) do
            tbl[#tbl + 1] = value
        end
    end
    self.tbl = tbl
    return self
end

---Filters the table based on the given type.
---@param strType string
---@return self
function t:OfType(strType)
    local tbl = {}
    for _, v in pairs(self.tbl) do
        if strType == type(v) then
            tbl[#tbl + 1] = v
        end
    end
    self.tbl = tbl
    return self
end

---Filters the table based on the given types.
---@param types table<string>
---@return self
function t:OfTypes(types)
    local set = {}
    for _, ty in pairs(types) do
        set[ty] = true
    end

    local tbl = {}
    for _, v in pairs(self.tbl) do
        if set[type(v)] then
            tbl[#tbl + 1] = v
        end
    end
    self.tbl = tbl
    return self
end

--#endregion

--#region Variables

--- Returns the first element that satisfies the predicate, or nil if none match.
---
--- Extra arguments after `predicate` are forwarded to it on every call, same as Where() -- see its
--- note on avoiding a fresh per-call closure.
---@param predicate fun(v: any, ...): boolean
---@param ... any Extra arguments forwarded to the predicate function.
---@return any
function t:Single(predicate, ...)
    for _, v in pairs(self.tbl) do
        if predicate(v, ...) then
            return v
        end
    end
    return nil
end

--- Returns the first matching element, or `default` if none satisfy the predicate.
---@param predicate fun(v: any): boolean
---@param default any
---@return any
function t:SingleOrDefault(predicate, default)
    for _, v in pairs(self.tbl) do
        if predicate(v) then
            return v
        end
    end
    return default
end

--- Returns true if at least one element satisfies the predicate.
---@param predicate fun(v: any): boolean
---@return boolean
function t:Any(predicate)
    for _, v in pairs(self.tbl) do
        if predicate(v) then
            return true
        end
    end
    return false
end

--- Returns true if every element satisfies the predicate.
---@param predicate fun(v: any): boolean
---@return boolean
function t:All(predicate)
    for _, v in pairs(self.tbl) do
        if not predicate(v) then
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
        chunk[#chunk + 1] = self.tbl[i]
        if i % size == 0 or i == num then
            result[#result + 1] = chunk
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
        tbl[#tbl + 1] = self.tbl[i]
    end
    self.tbl = tbl
    return self
end

--- Removes duplicate elements, keeping only the first occurrence of each value.
---@return self
function t:Distinct()
    local tbl = {}
    local seen = {}
    for _, v in pairs(self.tbl) do
        if not seen[v] then
            seen[v] = true
            tbl[#tbl + 1] = v
        end
    end
    self.tbl = tbl
    return self
end

--- Merges elements from another LINQ sequence, keeping only distinct values.
---@param tbl LINQ
---@return self
function t:Union(tbl)
    local seen = {}
    for _, v in pairs(self.tbl) do
        seen[v] = true
    end
    for _, v in pairs(tbl.tbl) do
        if not seen[v] then
            seen[v] = true
            self.tbl[#self.tbl + 1] = v
        end
    end
    return self
end

--- Keeps only elements that also exist in the other LINQ sequence.
---@param tbl LINQ
---@return self
function t:Intersect(tbl)
    local set = {}
    for _, v in pairs(tbl.tbl) do
        set[v] = true
    end
    local newTbl = {}
    for _, v in pairs(self.tbl) do
        if set[v] then
            newTbl[#newTbl + 1] = v
        end
    end
    self.tbl = newTbl
    return self
end

--- Appends all elements from another LINQ sequence, keeping duplicates.
---@param tbl LINQ
---@return self
function t:Concat(tbl)
    for _, v in pairs(tbl.tbl) do
        self.tbl[#self.tbl + 1] = v
    end
    return self
end

--- Groups elements into sub-tables keyed by the value returned from the selector.
---@param keySelector fun(v: any, k: any): any
---@return self
function t:GroupBy(keySelector)
    local tbl = {}
    for k, v in pairs(self.tbl) do
        local key = keySelector(v, k)
        local bucket = tbl[key]
        if not bucket then
            bucket = {}
            tbl[key] = bucket
        end
        bucket[#bucket + 1] = v
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
        tbl[#tbl + 1] = self.tbl[i]
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
        tbl[#tbl + 1] = self.tbl[i]
    end
    self.tbl = tbl
    return self
end

--- Skips elements from the start as long as the predicate holds, then keeps the rest.
---@param predicate fun(v: any): boolean
---@return self
function t:SkipWhile(predicate)
    local tbl = {}
    local skip = true
    for _, v in pairs(self.tbl) do
        if skip and not predicate(v) then
            skip = false
        end
        if not skip then
            tbl[#tbl + 1] = v
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
        tbl[#tbl + 1] = self.tbl[i]
    end
    self.tbl = tbl
    return self
end

---Takes the last n elements
---@param n number
---@return self
function t:TakeLast(n)
    local tbl = {}
    for i = math.max(1, #self.tbl - n + 1), #self.tbl do
        tbl[#tbl + 1] = self.tbl[i]
    end
    self.tbl = tbl
    return self
end

--- Takes elements from the start as long as the predicate holds, then stops.
---@param predicate fun(v: any, k: any): boolean
---@return self
function t:TakeWhile(predicate)
    local tbl = {}
    for k, v in pairs(self.tbl) do
        if not predicate(v, k) then
            break
        end
        tbl[#tbl + 1] = v
    end
    self.tbl = tbl
    return self
end

--#endregion
