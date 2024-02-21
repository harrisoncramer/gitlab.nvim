List = {}
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
  for i, v in ipairs(self) do
    result[i] = func(v)
  end
  return result
end

---Filters a given list
---@generic T
---@param func fun(v: T):boolean
---@return List<T> @Returns a new list of elements for which func returns true
function List:filter(func)
  local result = List.new()
  for i, v in ipairs(self) do
    if func(v) == true then
      result[i] = v
    end
  end
  return result
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
