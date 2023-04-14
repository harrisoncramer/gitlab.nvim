local function get_git_root()
  local output = vim.fn.system('git rev-parse --show-toplevel 2>/dev/null')
  if vim.v.shell_error == 0 then
    return vim.fn.substitute(output, '\n', '', '')
  else
    return nil
  end
end

local function get_relative_file_path()
  local git_root = get_git_root()
  if git_root ~= nil then
    local current_file = vim.fn.expand('%:p')
    return vim.fn.substitute(current_file, git_root .. '/', '', '')
  else
    return nil
  end
end

local get_current_line_number = function()
  return vim.api.nvim_call_function('line', { '.' })
end

function P(...)
  local objects = {}
  for i = 1, select("#", ...) do
    local v = select(i, ...)
    table.insert(objects, vim.inspect(v))
  end

  print(table.concat(objects, "\n"))
  return ...
end

local function get_buffer_text(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local text = table.concat(lines, "\n")
  return text
end

local M = {}
M.get_relative_file_path = get_relative_file_path
M.get_current_line_number = get_current_line_number
M.get_buffer_text = get_buffer_text
M.P = P
return M
