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

function List:find(func)
  for _, v in ipairs(self) do
    if func(v) == true then
      return v
    end
  end
  return nil
end

function List:slice(first, last, step)
  local sliced = {}
  for i = first or 1, last or #self, step or 1 do
    sliced[#sliced + 1] = self[i]
  end
  return sliced
end
