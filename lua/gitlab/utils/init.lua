local state = require("gitlab.state")

local function get_git_root()
  local output = vim.fn.system('git rev-parse --show-toplevel 2>/dev/null')
  if vim.v.shell_error == 0 then
    return vim.fn.substitute(output, '\n', '', '')
  else
    return nil
  end
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

local feature_branch_exists = function(base_branch)
  local is_git_branch = io.popen("git rev-parse --is-inside-work-tree 2>/dev/null"):read("*a")
  if is_git_branch == "true\n" then
    for line in io.popen("git branch 2>/dev/null"):lines() do
      line = line:gsub("%s+", "")
      if line == base_branch then
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

local base_invalid = function()
  local current_branch_raw = io.popen("git rev-parse --abbrev-ref HEAD"):read("*a")
  local current_branch = string.gsub(current_branch_raw, "\n", "")

  if current_branch == "main" or current_branch == "master" then
    vim.notify('On ' .. current_branch .. ' branch, no MRs available', vim.log.levels.ERROR)
    return true
  end

  local base = state.BASE_BRANCH
  local hasBaseBranch = feature_branch_exists(base)
  if not hasBaseBranch then
    vim.notify('No base branch. If this is a Gitlab repository, please check your setup function!', vim.log.levels.ERROR)
    return true
  end
end

local format_date = function(date_string)
  local year, month, day, hour, min, sec = date_string:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
  local date = os.time({ year = year, month = month, day = day, hour = hour, min = min, sec = sec })

  -- Format date into human-readable string without leading zeros
  local formatted_date = os.date("%A, %B %e at %l:%M %p", date)
  return formatted_date
end

local add_comment_sign = function(line_number)
  local bufnr = vim.api.nvim_get_current_buf()
  vim.cmd("sign define piet text= texthl=Substitute")
  vim.fn.sign_place(0, "piet", "piet", bufnr, { lnum = line_number })
end

local function jump_to_file(filename, line_number)
  if line_number == nil then line_number = 1 end
  vim.api.nvim_command("wincmd l")
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

local function find_value_by_id(tbl, id)
  for i = 1, #tbl do
    if tbl[i].id == tonumber(id) then
      return tbl[i]
    end
  end
  return nil
end

vim.cmd("highlight Gray guifg=#888888")
local function darken_metadata(bufnr, regex)
  local num_lines = vim.api.nvim_buf_line_count(bufnr)
  for i = 0, num_lines - 1 do
    local line = vim.api.nvim_buf_get_lines(bufnr, i, i + 1, false)[1]
    if string.match(line, regex) then
      vim.api.nvim_buf_add_highlight(bufnr, -1, 'Gray', i, 0, -1)
    end
  end
end

local function print_success(_, line)
  if line ~= nil and line ~= "" then
    vim.notify(line, vim.log.levels.INFO)
  end
end

local function print_error(_, line)
  if line ~= nil and line ~= "" then
    vim.notify(line, vim.log.levels.ERROR)
  end
end

local function exit(popup)
  popup:unmount()
end

local create_popup_state = function(title, width, height)
  return {
    buf_options = {
      filetype = 'markdown'
    },
    enter = true,
    focusable = true,
    border = {
      style = "rounded",
      text = {
        top = title
      },
    },
    position = "50%",
    size = {
      width = width,
      height = height,
    },
  }
end

local M = {}
M.merge_tables = function(defaults, overrides)
  local result = {}

  for key, value in pairs(defaults) do
    if type(value) == "table" then
      result[key] = M.merge_tables(value, overrides[key] or {})
    else
      result[key] = overrides[key] or value
    end
  end

  return result
end

local read_file = function(file_path)
  local file = io.open(file_path, "r")
  if file == nil then
    return nil
  end
  local file_contents = file:read("*all")
  file:close()
  file_contents = string.gsub(file_contents, "\n", "")
  return file_contents
end

local split_diff_view_filename = function(filename)
  local hash, path = filename:match("://%.git/(/?[0-9a-f]+)(/.*)$")
  if hash and path then
    path = path:gsub("%.git/", ""):gsub("^/", "")
    hash = hash:gsub("^/", "")
  end
  return hash, path
end

local current_file_path = function()
  local path = debug.getinfo(1, 'S').source:sub(2)
  return vim.fn.fnamemodify(path, ':p')
end


M.get_relative_file_path = get_relative_file_path
M.get_current_line_number = get_current_line_number
M.get_buffer_text = get_buffer_text
M.feature_branch_exists = feature_branch_exists
M.press_enter = press_enter
M.string_starts = string_starts
M.base_invalid = base_invalid
M.format_date = format_date
M.add_comment_sign = add_comment_sign
M.jump_to_file = jump_to_file
M.find_value_by_id = find_value_by_id
M.darken_metadata = darken_metadata
M.print_success = print_success
M.print_error = print_error
M.create_popup_state = create_popup_state
M.exit = exit
M.read_file = read_file
M.split_diff_view_filename = split_diff_view_filename
M.branch_exists = branch_exists
M.current_file_path = current_file_path
M.P = P
return M
