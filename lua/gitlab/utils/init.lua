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

local branch_exists = function(b)
  local is_git_branch = io.popen("git rev-parse --is-inside-work-tree 2>/dev/null"):read("*a")
  if is_git_branch == "true\n" then
    for line in io.popen("git branch 2>/dev/null"):lines() do
      line = line:gsub("%s+", "")
      if line == b then
        return true
      end
    end
  end
  return false
end

local string_starts = function(str, start)
  return str:sub(1, #start) == start
end

local press_enter = function()
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", false, true, true), "n", false)
end

local baseInvalid = function()
  local u = require("gitlab.utils")
  local base = require("gitlab").BASE_BRANCH
  local hasBaseBranch = u.branch_exists(base)
  if not hasBaseBranch then
    require("notify")('No base branch. If this is a Gitlab repository, please check your setup function!', "error")
    return true
  end
end

local formatDate = function(date_string)
  local year, month, day, hour, min, sec = date_string:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
  local date = os.time({ year = year, month = month, day = day, hour = hour, min = min, sec = sec })

  -- Format date into human-readable string without leading zeros
  local formatted_date = os.date("%A, %B %e at%l:%M %p", date)
  return formatted_date
end

local add_comment_sign = function(line_number)
  local bufnr = vim.api.nvim_get_current_buf()
  vim.cmd("sign define piet text= texthl=Substitute")
  vim.fn.sign_place(0, "piet", "piet", bufnr, { lnum = line_number })
end

local function jump_to_file(filename, line_number)
  -- Check if the buffer with the given filename is already open
  local bufnr = vim.fn.bufnr(filename)
  if bufnr ~= -1 then
    -- Buffer is already open, switch to it
    vim.cmd("buffer " .. bufnr)
    vim.api.nvim_win_set_cursor(0, { line_number, 0 })
    return
  end

  -- If buffer is not already open, open it
  vim.cmd("edit " .. filename)
  vim.api.nvim_win_set_cursor(0, { line_number, 0 })
end

local function findValueById(tbl, id)
  for i = 1, #tbl do
    if tbl[i].id == tonumber(id) then
      return tbl[i]
    end
  end
  return nil
end

local M = {}
M.get_relative_file_path = get_relative_file_path
M.get_current_line_number = get_current_line_number
M.get_buffer_text = get_buffer_text
M.branch_exists = branch_exists
M.press_enter = press_enter
M.string_starts = string_starts
M.baseInvalid = baseInvalid
M.formatDate = formatDate
M.add_comment_sign = add_comment_sign
M.jump_to_file = jump_to_file
M.findValueById = findValueById

M.P = P
return M
