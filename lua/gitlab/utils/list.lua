List = {}
List.__index = List

function List.new(t)
  local list = t or {}
  setmetatable(list, List)
  return list
end

function List:map(func)
  local result = List.new()
  for i, v in ipairs(self) do
    result[i] = func(v)
  end
  return result
end

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
