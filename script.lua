local combine = function(t1, ...)
  local result = t1
  local tables = { ... }
  for _, t in ipairs(tables) do
    for _, v in ipairs(t) do
      table.insert(result, v)
    end
  end
  return result
end

vim.print(combine({ 1, 2, 3 }, { 4, 5, 6 }, { 7, 8, 9 }))
