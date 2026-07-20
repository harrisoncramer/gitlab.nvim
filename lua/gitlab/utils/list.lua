---@class List<T>
local List = {}
List.__index = List

---Create a new List from a provided table or from an empty table.
---@generic T
---@param t? T[]
---@return List<T>
function List.new(t)
  local list = t or {}
  setmetatable(list, List)
  return list
end

---Return a new list of elements mutated by func.
---@generic T
---@generic U
---@param self List<T>
---@param func fun(v: T):U
---@return List<U>
function List:map(func)
  local result = List.new()
  for _, v in ipairs(self) do
    table.insert(result, func(v))
  end
  return result
end

---Return a new list of elements for which func returns true.
---@generic T
---@param self List<T>
---@param func fun(v: T, i: integer):boolean
---@return List<T>
function List:filter(func)
  local result = List.new()
  for i, v in ipairs(self) do
    if func(v, i) == true then
      table.insert(result, v)
    end
  end
  return result
end

---Return two lists: With elements for which func returns true, or false.
---@generic T
---@param self List<T>
---@param func fun(v: T, i: integer):boolean
---@return List<T>, List<T>
function List:partition(func)
  local result_true = List.new()
  local result_false = List.new()
  for i, v in ipairs(self) do
    if func(v, i) == true then
      table.insert(result_true, v)
    else
      table.insert(result_false, v)
    end
  end
  return result_true, result_false
end

---Apply func to list elements to reduce the list to a single value.
---@generic T, U
---@param self List<T>
---@param func fun(agg: U, v: T, i: integer):U
---@param agg U
---@return U
function List:reduce(func, agg)
  for i, v in ipairs(self) do
    agg = func(agg, v, i)
  end
  return agg
end

---Sort the list in place based on a comparator func.
---@generic T
---@param self List<T>
---@param func fun(a: T, b: T):boolean
---@return List<T>
function List:sort(func)
  local result = List.new(self)
  table.sort(result, func)
  return result
end

---Return the first element in the list that satisfies the callback func, or nil.
---@generic T
---@param self List<T>
---@param func fun(a: T):boolean
---@return T?
function List:find(func)
  for _, v in ipairs(self) do
    if func(v) == true then
      return v
    end
  end
  return nil
end

---Return a portion of the list between start and end indices.
---@generic T
---@param self List<T>
---@param first integer The index of the first item to include
---@param last integer The index of the last item to include
---@param step? integer The step to increment the index (default: 1)
---@return List<T>
function List:slice(first, last, step)
  local sliced = List.new()
  for i = first or 1, last or #self, step or 1 do
    sliced[#sliced + 1] = self[i]
  end
  return sliced
end

---Return true if any of the elements can satisfy the callback func, otherwise false.
---@generic T
---@param self List<T>
---@param func fun(v: T, i: integer):boolean
---@return boolean
function List:includes(func)
  for i, v in ipairs(self) do
    if func(v, i) == true then
      return true
    end
  end
  return false
end

---Return an iterator over the list's values.
---@generic T
---@param self List<T>
---@return T[]
function List:values()
  local result = {}
  for _, v in ipairs(self) do
    table.insert(result, v)
  end
  return result
end

return List
