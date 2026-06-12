-- This has become a huge garbage can for helper functions.
-- TODO: Consider splitting this into meaningful modules.

local git = require("gitlab.git")
local List = require("gitlab.utils.list")

local M = {}

---Pull out a list of values matching a given key from an array of tables.
---@param t table List of tables to search
---@param key string Value to search for in the list
---@return table
M.extract = function(t, key)
  local resultTable = {}
  for _, value in ipairs(t) do
    if value[key] then
      table.insert(resultTable, value[key])
    end
  end
  return resultTable
end

---Return the first value in the input table or nil if there are no values in the table.
---This is useful for cases where we want to get the first non-nil boolean value, but
---`b ~= nil and b or c` would evaluate to `c` if `b` was `false`.
---Note: Lua removes `nil` values from a table automatically.
---@param values boolean[] The list of input values
---@return boolean
M.get_first_non_nil_value = function(values)
  for _, val in pairs(values) do
    if val ~= nil then
      return val
    end
  end
end

---Return whether a string ends with a suffix (true if suffix is empty).
---@param str string
---@param suffix string
---@return boolean
M.ends_with = function(str, suffix)
  return suffix == "" or str:sub(-#suffix) == suffix
end

---Return a copy of `input_table` with `value_to_remove` removed.
---@generic T
---@param input_table T[]
---@param value_to_remove T
---@return T[]
M.filter = function(input_table, value_to_remove)
  local result = {}
  for _, v in ipairs(input_table) do
    if v ~= value_to_remove then
      table.insert(result, v)
    end
  end
  return result
end

---Merge two deeply nested tables overriding values from the first in case of conflicts.
---@param defaults table The first table
---@param overrides table The second table
---@return table
M.merge = function(defaults, overrides)
  if type(defaults) == "table" and M.table_size(defaults) == 0 and type(overrides) == "table" then
    return overrides
  end
  return vim.tbl_deep_extend("force", defaults, overrides)
end

---Combine list-like (non associative) tables in input order, keeping values from all.
---@param ... table The tables to combine
---@return table
M.combine = function(...)
  local result = {}
  local tables = { ... }
  for _, t in ipairs(tables) do
    for _, v in ipairs(t) do
      table.insert(result, v)
    end
  end
  return result
end

---Pluralize the input word if necessary, e.g. "3 minutes", but "1 minute".
---TODO: Fix "-1" which produces "-1 minutes".
---@param num integer The count of the item/word
---@param word string The word to pluralize
---@return string
M.pluralize = function(num, word)
  return num .. string.format(" %s", word) .. ((num > 1 or num <= 0) and "s" or "")
end

---Provide a human readable time since a given ISO date string.
---TODO: Verify that time zone is handled correctly by this function. Current date is
---calculated as Coordinated Universal Time, but the reference `date_string` seems to be
---taken at face value. This should handle date_string formats like
---"2026-06-23T15:31:08.521+02:00", and "2026-05-24T14:50:46.096Z"
---@param date_string string The ISO time stamp to compare with the current time
---@param current_date_table? osdate Only used in tests. Table with YYYY, MM, DD, HH, MM, SS, weekday (Sunday is 1), day of the year, and boolean daylight saving flag
---@return string
M.time_since = function(date_string, current_date_table)
  local dt = current_date_table or os.date("!*t")
  local year, month, day, hour, min, sec = date_string:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
  local date = os.time({ year = year, month = month, day = day, hour = hour, min = min, sec = sec })

  local current_date = os.time({
    year = dt.year,
    month = dt.month,
    day = dt.day,
    hour = dt.hour,
    min = dt.min,
    sec = dt.sec,
  })

  local time_diff = current_date - date

  if time_diff < 60 then
    return "just now"
  elseif time_diff < 3600 then
    return M.pluralize(math.floor(time_diff / 60), "minute") .. " ago"
  elseif time_diff < 86400 then
    return M.pluralize(math.floor(time_diff / 3600), "hour") .. " ago"
  elseif time_diff < 2592000 then
    return M.pluralize(math.floor(time_diff / 86400), "day") .. " ago"
  else
    local formatted_date = os.date("%B %e, %Y", date)
    return tostring(formatted_date)
  end
end

---Spread all the values from t2 into t1.
---TODO: Replace with M.combine.
---@param t1 table The first table (gets the values)
---@param t2 table The second table
---@return table
M.spread = function(t1, t2)
  for _, value in ipairs(t2) do
    table.insert(t1, value)
  end

  return t1
end

---Return the number of keys or values in a table.
---TODO: Replace with next().
---@param t table The table to count
---@return integer
M.table_size = function(t)
  local count = 0
  for _ in pairs(t) do
    count = count + 1
  end
  return count
end

---Return whether a given value is in a list or not.
---@param list table The list to search
---@return boolean
M.contains = function(list, search_value)
  for _, value in pairs(list) do
    if value == search_value then
      return true
    end
  end
  return false
end

---Split a string by new lines and return an iterator.
-- TODO: Replace newline hack with s:gmatch("[^\r\n]+"), add tests.
---@param s string The string to split
---@return fun():string new_lines The iterator object
M.split_by_new_lines = function(s)
  if s:sub(-1) ~= "\n" then
    s = s .. "\n"
  end -- Append a new line to the string, if there's none, otherwise the last line would be lost.
  return s:gmatch("(.-)\n") -- Match 0 or more (as few as possible) characters followed by a new line.
end

---Take a string of newline-separated lines and return a table of lines.
---@param s string The string to parse
---@return table
M.lines_into_table = function(s)
  local lines = {}
  for line in M.split_by_new_lines(s) do
    table.insert(lines, line)
  end
  return lines
end

---Return a new list which is a copy of `list` with the order reversed.
---@generic T
---@param list T[] The list to reverse
---@return T[]
M.reverse = function(list)
  if #list == 0 then
    return list
  end
  local rev = {}
  for i = #list, 1, -1 do
    rev[#rev + 1] = list[i]
  end
  return rev
end

---Return the value in seconds of a time offset.
---@param offset string The offset to compare, e.g. "-0500" for EST
---@return integer
M.offset_to_seconds = function(offset)
  local sign, hours, minutes = offset:match("([%+%-])(%d%d)(%d%d)")
  local offset_in_seconds = tonumber(hours) * 3600 + tonumber(minutes) * 60
  if sign == "-" then
    offset_in_seconds = -offset_in_seconds
  end
  return offset_in_seconds
end

---Convert a UTC timestamp and offset to a human readable datestring.
---TODO: 1. Always called with vim.fn.strftime("%z") as `offset` outside of tests,
---         consider using it as a "default" value
---      2. Simplify the triple date_string:match
---      3. Simplify the time zone offset calculation
---      4. Use YYYY-MM-DD instead of MM/DD/YYYY in return statement (https://xkcd.com/1179/)
---@param date_string string The time stamp
---@param offset string The offset of the user's local time zone, e.g. -0500 for EST
---@return string
M.format_to_local = function(date_string, offset)
  -- ISO 8601 format
  -- 2021-01-01T00:00:00.000Z
  local year, month, day, hour, min, sec, _, tzOffset = date_string:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+).(%d+)Z")
  if year == nil then
    -- ISO 8601 format with timezone offset
    -- 2021-01-01T00:00:00.000-05:00
    local tzOffsetSign, tzOffsetHour, tzOffsetMin
    year, month, day, hour, min, sec, _, tzOffsetSign, tzOffsetHour, tzOffsetMin =
      date_string:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+).(%d+)([%+%-])(%d%d):(%d%d)")

    -- ISO 8601 format with just "Z" (aka no time offset)
    -- 2021-01-01T00:00:00Z
    if year == nil then
      year, month, day, hour, min, sec = date_string:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)Z")
      tzOffsetSign = "-"
      tzOffsetHour = "00"
      tzOffsetMin = "00"
    end

    if year == nil then
      return "Date Unparseable"
    end

    tzOffset = tzOffsetSign .. tzOffsetHour .. tzOffsetMin
  end

  local localTime = os.time({
    year = year,
    month = month,
    day = day,
    hour = hour,
    min = min,
    sec = sec,
    tzOffset = tzOffset,
  })

  -- Subtract the tzOffset from the local time to get the UTC time
  local localTimestamp = tzOffset ~= nil and localTime - M.offset_to_seconds(tzOffset) or localTime
  localTimestamp = localTimestamp + M.offset_to_seconds(offset)

  return tostring(os.date("%m/%d/%Y at %H:%M", localTimestamp))
end

---Return a comma separated (human readable) list of values from a list of associative tables.
---@param list_of_tables table The list to traverse
---@param key string The key of the values to pull from the tables
---@return string
M.make_readable_list = function(list_of_tables, key)
  local res = ""
  for i, t in ipairs(list_of_tables) do
    res = res .. t[key]
    if i < #list_of_tables then
      res = res .. ", "
    end
  end
  return res
end

---Return the length of the longest string in a list of strings.
---@param strings string[]
---@return integer
M.get_max_length = function(strings)
  local longest = 0
  for _, v in pairs(strings) do
    if vim.fn.strcharlen(v) > longest then
      longest = vim.fn.strcharlen(v)
    end
  end
  return longest
end

---Return table `tbl` with function `f` applied to each value in the table.
---TODO: The only use of this function can be replaced by M.extract(t, "name").
---@generic K, V, U
---@param tbl table<K, V>
---@param f fun(value: V): U
---@return table<K, U>
M.map = function(tbl, f)
  local t = {}
  for k, v in pairs(tbl) do
    t[k] = f(v)
  end
  return t
end

---Notify user with a message with a prepended plugin identifier.
---@param msg string
---@param lvl vim.log.levels
M.notify = function(msg, lvl)
  vim.notify("gitlab.nvim: " .. msg, lvl)
end

---Re-raise Vimscript error message after removing existing message prefixes.
---This is used instead of plain M.notify to suppress double use of the gitlab.nvim
---prefix in vimscript errors that called gitlab.nvim's API.
---@param msg string
---@param lvl vim.log.levels
M.notify_vim_error = function(msg, lvl)
  M.notify(msg:gsub("^Vim:", ""):gsub("^gitlab.nvim: ", ""), lvl)
end

---Return true when running on Windows.
---@return boolean
M.is_windows = function()
  if vim.fn.has("win32") == 1 or vim.fn.has("win32unix") == 1 then
    return true
  end
  return false
end

---Path separator based on current OS.
---@type string
M.path_separator = M.is_windows() and "\\" or "/"

---Split path by OS path separator.
---@param path string
---@return string[]
M.split_path = function(path)
  local path_parts = {}
  for part in string.gmatch(path, "([^" .. M.path_separator .. "]+)") do
    table.insert(path_parts, part)
  end
  return path_parts
end

---Return the contents of a buffer as a string with lines separated by the '\n' character.
---@param bufnr integer
---@return string
M.get_buffer_text = function(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return ""
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local text = table.concat(lines, "\n")
  return text
end

---Return the number of lines in the buffer. Returns 1 even for empty buffers.
---@param bufnr integer
---@return integer
M.get_buffer_length = function(bufnr)
  return #vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
end

---Convert string to corresponding Boolean.
---@param str string
---@return boolean
M.string_to_bool = function(str)
  str = vim.fn.trim(str)
  if str == "true" or str == "True" or str == "TRUE" then
    return true
  elseif str == "false" or str == "False" or str == "FALSE" then
    return false
  end
  return false
end

---Convert Boolean to corresponding string.
---@param bool boolean
---@return string
M.bool_to_string = function(bool)
  if bool == true then
    return "true"
  end
  return "false"
end

---Toggle Boolean value.
---@param bool string
---@return string
M.toggle_string_bool = function(bool)
  local string_bools = {
    ["true"] = "false",
    ["True"] = "False",
    ["TRUE"] = "FALSE",
    ["false"] = "true",
    ["False"] = "True",
    ["FALSE"] = "TRUE",
  }
  -- TODO: Just do one replacement with "%s+".
  bool = bool:gsub("^%s+", ""):gsub("%s+$", "")
  local toggled = string_bools[bool]
  if toggled == nil then
    M.notify(("Cannot toggle value '%s'"):format(bool), vim.log.levels.ERROR)
    return bool
  end
  return toggled
end

---Simulate the user pressing the <Esc> key in order to get into normal mode.
M.press_escape = function()
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", false, true, true), "nx", false)
end

---Return timestamp from ISO 8601 formatted date string.
---@param date_string string ISO 8601 formatted date string
---@return integer timestamp
M.from_iso_format_date_to_timestamp = function(date_string)
  local year, month, day, hour, min, sec = date_string:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
  return os.time({ year = year, month = month, day = day, hour = hour, min = min, sec = sec })
end

---Return a copy of `a` without the items that are also in `b`.
---@generic T
---@param a T[]
---@param b T[]
---@return T[]
M.difference = function(a, b)
  local set_b = {}
  for _, val in ipairs(b) do
    set_b[val] = true
  end

  local not_included = {}
  for _, val in ipairs(a) do
    if not set_b[val] then
      table.insert(not_included, val)
    end
  end

  return not_included
end

---@class ReadFileOpts
---@field remove_newlines? boolean

---Return the contents of a file as a string.
---@param file_path string
---@param opts? ReadFileOpts
---@return string?
M.read_file = function(file_path, opts)
  local file = io.open(file_path, "r")
  if file == nil then
    return nil
  end
  local file_contents = file:read("*all")
  file:close()

  if opts and opts.remove_newlines then
    file_contents = string.gsub(file_contents, "\n", "")
  end

  return file_contents
end

---Return the root path of the plugin (four levels up from this file: lua/gitlab/utils/init.lua)
---@return string
M.get_root_path = function()
  local path = debug.getinfo(1, "S").source:sub(2)
  return vim.fn.fnamemodify(path, ":p:h:h:h:h")
end

---Return the specified line of the given (or current) buffer.
---@param bufnr? integer The buffer to get the line from. If nil, the current buffer is used
---@param linenr integer The 1-indexed line number to return
---@return string
M.get_line_content = function(bufnr, linenr)
  local current_buffer = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr ~= nil and bufnr or current_buffer, linenr - 1, linenr, false)
  return lines[1]
end

---Switch if buffer can be modified.
---@param buf integer Buffer number
---@param bool boolean The value to set
M.switch_can_edit_buf = function(buf, bool)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  vim.api.nvim_set_option_value("modifiable", bool, { buf = buf })
  vim.api.nvim_set_option_value("readonly", not bool, { buf = buf })
end

---Return the window holding a buffer in the current tab page.
---@param buffer_id integer Id of a buffer
---@return integer?
M.get_window_id_by_buffer_id = function(buffer_id)
  local tabpage = vim.api.nvim_get_current_tabpage()
  local windows = vim.api.nvim_tabpage_list_wins(tabpage)

  return List.new(windows):find(function(win_id)
    local buf_id = vim.api.nvim_win_get_buf(win_id)
    return buf_id == buffer_id
  end)
end

---Return the list of file and directory names in the given directory, sorted by the
---last modification time from newest to oldest.
---@param folder_path string
---@return string[]? files
M.list_files_in_folder = function(folder_path)
  if vim.fn.isdirectory(folder_path) == 0 then
    return nil
  end

  local folder_ok, folder = pcall(vim.fn.readdir, folder_path)

  if not folder_ok then
    return nil
  end

  local files = {}
  if folder ~= nil then
    files = List.new(folder)
      :map(function(file)
        local file_path = folder_path .. M.path_separator .. file
        local timestamp = vim.fn.getftime(file_path)
        return { name = file, timestamp = timestamp }
      end)
      :sort(function(a, b)
        return a.timestamp > b.timestamp
      end)
      :map(function(file)
        return file.name
      end)
  end

  return files
end

---Return true if current mode is visual mode, otherwise false.
---TODO: Move to lua/gitlab/actions/comment.lua where is its only call site.
---@return boolean
M.check_visual_mode = function()
  local mode = vim.api.nvim_get_mode().mode
  if mode ~= "v" and mode ~= "V" then
    M.notify("Code suggestions and multiline comments are only available in visual mode", vim.log.levels.ERROR)
    return false
  end
  return true
end

---Return start line and end line of visual selection.
---TODO: Move to `lua/gitlab/reviewer/location.lua`
---@return integer
---@return integer
M.get_visual_selection_boundaries = function()
  local start_line = vim.fn.line("v")
  local end_line = vim.fn.line(".")
  if start_line > end_line then
    start_line, end_line = end_line, start_line
  end
  return start_line, end_line
end

---Get icon for filename if nvim-web-devicons plugin is available, otherwise return
---empty string.
---@return string?
---@return string?
M.get_icon = function(filename)
  local has_devicons, devicons = pcall(require, "nvim-web-devicons")
  if has_devicons then
    local extension = vim.fn.fnamemodify(filename, ":e")
    local icon, icon_hl = devicons.get_icon(filename, extension, { default = true })
    if icon ~= nil then
      return icon .. " ", icon_hl
    else
      return nil, nil
    end
  else
    return nil, nil
  end
end

---Return content between start_line and end_line.
---TODO: Consider removing this thin wrapper.
---@param start_line integer
---@param end_line integer
---@return string[]
M.get_lines = function(start_line, end_line)
  return vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
end

---Select a git branch and perform callback with the branch as an argument.
---@param cb function The callback to perform with the selected branch
M.select_target_branch = function(cb)
  local all_branch_names = git.get_all_merge_targets()
  if not all_branch_names then
    return
  end
  vim.ui.select(all_branch_names, {
    prompt = "Choose target branch for merge",
  }, function(choice)
    if choice then
      cb(choice)
    end
  end)
end

---Return the project's Gitlab URL.
---@return string?
M.get_web_url = function()
  local web_url = require("gitlab.state").INFO.web_url
  if web_url ~= nil then
    return web_url
  end
  M.notify("Could not get Gitlab URL", vim.log.levels.ERROR)
end

---Open the `url` based on OS.
---@param url? string
M.open_in_browser = function(url)
  if vim.fn.has("mac") == 1 then
    vim.fn.jobstart({ "open", url })
  elseif vim.fn.has("win32") == 1 then
    vim.fn.jobstart({ "cmd", "/c", "start", url })
  elseif vim.fn.has("unix") == 1 then
    vim.fn.jobstart({ "xdg-open", url })
  else
    M.notify("Opening a Gitlab URL is not supported on this OS!", vim.log.levels.ERROR)
  end
end

---Combine two tables.
---TODO: Replace with M.combine.
---@param t1 table
---@param t2 table
---@return table
M.join = function(t1, t2)
  local res = {}
  for _, val in ipairs(t1) do
    table.insert(res, val)
  end
  for _, val in ipairs(t2) do
    table.insert(res, val)
  end
  return res
end

---Trim the trailing slash from a URL
---@param s string
---@return string
M.trim_slash = function(s)
  return (s:gsub("/+$", ""))
end

---Return an empty table if `data` is nil, otherwise return `data` unchanged.
---@param data? table|vim.NIL
---@return table
M.ensure_table = function(data)
  if data == vim.NIL or data == nil then
    return {}
  end
  return data
end

---Return the value of a `field` from `tbl`.
---Recurses into subtables, if the field name contains "." characters, e.g.,
---get_nested_field({subtable = {field = 1}}, "subtable.field") will return `1`
---@param tbl table
---@param field string The field to return
---@return any
M.get_nested_field = function(tbl, field)
  local subfield = string.match(field, "[^.]+")
  local subtable = tbl[subfield]
  if subtable ~= nil then
    local new_field = string.gsub(field, "^" .. subfield .. ".?", "")
    if new_field ~= "" then
      return M.get_nested_field(subtable, new_field)
    else
      return subtable
    end
  end
end

---Open one fold level if there are closed folds under the cursor.
M.open_fold_under_cursor = function()
  if vim.fn.foldclosed(vim.fn.line(".")) > -1 then
    vim.cmd("normal! zo")
  end
end

return M
