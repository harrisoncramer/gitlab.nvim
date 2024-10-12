local List = {}
List.__index = List

function List.new(t)
  local list = t or {}
  setmetatable(list, List)
  return list
end

---Mutates a given list
---@generic T
---@param func fun(v: T):T
---@return List<T> @Returns a new list of elements mutated by func
function List:map(func)
  local result = List.new()
  for _, v in ipairs(self) do
    table.insert(result, func(v))
  end
  return result
end

---Filters a given list
---@generic T
---@param func fun(v: T, i: integer):boolean
---@return List<T> @Returns a new list of elements for which func returns true
function List:filter(func)
  local result = List.new()
  for i, v in ipairs(self) do
    if func(v, i) == true then
      table.insert(result, v)
    end
  end
  return result
end

---Partitions a given list into two lists
---@generic T
---@param func fun(v: T, i: integer):boolean
---@return List<T>, List<T> @Returns two lists: the 1st with elements for which func returns true, the 2nd with elements for which it returns false
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

function List:reduce(func, agg)
  for i, v in ipairs(self) do
    agg = func(agg, v, i)
  end
  return agg
end

function List:sort(func)
  local result = List.new(self)
  table.sort(result, func)
  return result
end

function List:find(func)
  for _, v in ipairs(self) do
    if func(v) == true then
      return v
    end
  end
  return nil
end

function List:slice(first, last, step)
  local sliced = List.new()
  for i = first or 1, last or #self, step or 1 do
    sliced[#sliced + 1] = self[i]
  end
  return sliced
end

---Returns true if any of the elements can satisfy the callback
---@generic T
---@param func fun(v: T, i: integer):boolean
---@return List<T> @Returns a boolean
function List:includes(func)
  for i, v in ipairs(self) do
    if func(v, i) == true then
      return true
    end
  end
  return false
end

function List:values()
  local result = {}
  for _, v in ipairs(self) do
    table.insert(result, v)
  end
  return result
end

return List
