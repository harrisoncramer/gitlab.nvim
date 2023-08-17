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

local string_starts = function(str, start)
  return str:sub(1, #start) == start
end

local press_enter = function()
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", false, true, true), "n", false)
end

local format_date = function(date_string)
  local date_table = os.date("!*t")
  local year, month, day, hour, min, sec = date_string:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
  local date = os.time({ year = year, month = month, day = day, hour = hour, min = min, sec = sec })

  local current_date = os.time({
    year = date_table.year,
    month = date_table.month,
    day = date_table.day,
    hour = date_table.hour,
    min = date_table.min,
    sec = date_table.sec
  })

  local time_diff = current_date - date

  if time_diff < 60 then
    return time_diff .. " seconds ago"
  elseif time_diff < 3600 then
    return math.floor(time_diff / 60) .. " minutes ago"
  elseif time_diff < 86400 then
    return math.floor(time_diff / 3600) .. " hours ago"
  elseif time_diff < 2592000 then
    return math.floor(time_diff / 86400) .. " days ago"
  else
    local formatted_date = os.date("%A, %B %e", date)
    return formatted_date
  end
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
    relative = "editor",
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

local random = math.random
local function uuid()
  local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
  return string.gsub(template, '[xy]', function(c)
    local v = (c == 'x') and random(0, 0xf) or random(8, 0xb)
    return string.format('%x', v)
  end)
end

local attach_uuid = function(str)
  return { text = str, id = uuid() }
end

local join_tables = function(table1, table2)
  for _, value in ipairs(table2) do
    table.insert(table1, value)
  end

  return table1
end

local contains = function(array, search_value)
  for _, value in ipairs(array) do
    if value == search_value then
      return true
    end
  end
  return false
end

local extract = function(t, property)
  local resultTable = {}
  for _, value in ipairs(t) do
    if value[property] then
      table.insert(resultTable, value[property])
    end
  end
  return resultTable
end

local remove_last_chunk = function(sentence)
  local words = {}
  for word in sentence:gmatch("%S+") do
    table.insert(words, word)
  end
  table.remove(words, #words)
  local sentence_without_last = table.concat(words, " ")
  return sentence_without_last
end

M.remove_last_chunk = remove_last_chunk
M.extract = extract
M.contains = contains
M.attach_uuid = attach_uuid
M.join_tables = join_tables
M.get_relative_file_path = get_relative_file_path
M.get_current_line_number = get_current_line_number
M.get_buffer_text = get_buffer_text
M.press_enter = press_enter
M.string_starts = string_starts
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
