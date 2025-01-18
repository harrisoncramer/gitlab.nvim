local git = require("gitlab.git")
local List = require("gitlab.utils.list")
local has_devicons, devicons = pcall(require, "nvim-web-devicons")
local M = {}

---Pulls out a list of values matching a given key from an array of tables
---@param t table List of tables to search
---@param key string Value to search for in the list
---@return table List List of values that were extracted
M.extract = function(t, key)
  local resultTable = {}
  for _, value in ipairs(t) do
    if value[key] then
      table.insert(resultTable, value[key])
    end
  end
  return resultTable
end

---Get the last word in a sentence
---@param sentence string The string to get the last word from
---@param divider string The regex to split the sentence by, defaults to whitespace
---@return string
M.get_last_word = function(sentence, divider)
  local words = {}
  local pattern = string.format("([^%s]+)", divider or " ")
  for word in sentence:gmatch(pattern) do
    table.insert(words, word)
  end
  return words[#words] or ""
end

---Return the first non-nil value in the input table, or nil
---@param values table The list of input values
---@return any
M.get_first_non_nil_value = function(values)
  for _, val in pairs(values) do
    if val ~= nil then
      return val
    end
  end
end

---Returns whether a string ends with a substring
---@param str string
---@param ending string
---@return boolean
M.ends_with = function(str, ending)
  return ending == "" or str:sub(-#ending) == ending
end

M.filter = function(input_table, value_to_remove)
  local resultTable = {}
  for _, v in ipairs(input_table) do
    if v ~= value_to_remove then
      table.insert(resultTable, v)
    end
  end
  return resultTable
end

M.filter_by_key_value = function(input_table, target_key, target_value)
  local result_table = {}
  for _, v in ipairs(input_table) do
    if v[target_key] ~= target_value then
      table.insert(result_table, v)
    end
  end
end

---Merges two deeply nested tables together, overriding values from the first with conflicts
---@param defaults table The first table
---@param overrides table The second table
---@return table
M.merge = function(defaults, overrides)
  if type(defaults) == "table" and M.table_size(defaults) == 0 and type(overrides) == "table" then
    return overrides
  end
  return vim.tbl_deep_extend("force", defaults, overrides)
end

---Combines two list-like (non associative) tables, keeping values from both
---@param t1 table The first table
---@param ... table[] The first table
---@return table
M.combine = function(t1, ...)
  local result = t1
  local tables = { ... }
  for _, t in ipairs(tables) do
    for _, v in ipairs(t) do
      table.insert(result, v)
    end
  end
  return result
end

---Pluralizes the input word, e.g. "3 cows"
---@param num integer The count of the item/word
---@param word string The word to pluralize
---@return string
M.pluralize = function(num, word)
  return num .. string.format(" %s", word) .. ((num > 1 or num <= 0) and "s" or "")
end

--- Provides a human readable time since a given ISO date string
---@param date_string string -- The ISO time stamp to compare with the current time
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

---Removes the first value from a list and returns the new, smaller list
---@param tbl table The table
---@return table
M.remove_first_value = function(tbl)
  local sliced_list = {}
  if M.table_size(tbl) <= 1 then
    return sliced_list
  end
  for i = 2, #tbl do
    table.insert(sliced_list, tbl[i])
  end

  return sliced_list
end

---Spreads all the values from t2 into t1
---@param t1 table The first table (gets the values)
---@param t2 table The second table
---@return table
M.spread = function(t1, t2)
  for _, value in ipairs(t2) do
    table.insert(t1, value)
  end

  return t1
end

---Returns the number of keys or values in a table
---@param t table The table to count
---@return integer
M.table_size = function(t)
  local count = 0
  for _ in pairs(t) do
    count = count + 1
  end
  return count
end

---Returns whether a given value is in a list or not
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

---Trims whitespace from a string
---@param s string The string to trim
---@return string
M.trim = function(s)
  local res = s:gsub("^%s+", ""):gsub("%s+$", "")
  return res
end

---Splits a string by new lines and returns an iterator
---@param s string The string to split
---@return table: An iterator object
M.split_by_new_lines = function(s)
  if s:sub(-1) ~= "\n" then
    s = s .. "\n"
  end -- Append a new line to the string, if there's none, otherwise the last line would be lost.
  return s:gmatch("(.-)\n") -- Match 0 or more (as few as possible) characters followed by a new line.
end

---Takes a string of lines and returns a table of lines
---@param s string The string to parse
---@return table
M.lines_into_table = function(s)
  local lines = {}
  for line in M.split_by_new_lines(s) do
    table.insert(lines, line)
  end
  return lines
end

-- Reverses the order of elements in a list
---@param list table The list to reverse
---@return table
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

---Returns the difference between a time offset and UTC time, in seconds
---@param offset string The offset to compare, e.g. -0500 for EST
---@return number
M.offset_to_seconds = function(offset)
  local sign, hours, minutes = offset:match("([%+%-])(%d%d)(%d%d)")
  local offset_in_seconds = tonumber(hours) * 3600 + tonumber(minutes) * 60
  if sign == "-" then
    offset_in_seconds = -offset_in_seconds
  end
  return offset_in_seconds
end

---Converts a UTC timestamp and offset to a human readable datestring
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

-- Returns a comma separated (human readable) list of values from a list of associative tables
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

-- Returns the length of the longest string in a list of strings
---@param list table The list of strings
---@return number
M.get_longest_string = function(list)
  local longest = 0
  for _, v in pairs(list) do
    if string.len(v) > longest then
      longest = string.len(v)
    end
  end
  return longest
end

M.map = function(tbl, f)
  local t = {}
  for k, v in pairs(tbl) do
    t[k] = f(v)
  end
  return t
end

M.reduce = function(tbl, agg, f)
  for _, v in pairs(tbl) do
    agg = f(agg, v)
  end
  return agg
end

M.notify = function(msg, lvl)
  vim.notify("gitlab.nvim: " .. msg, lvl)
end

-- Re-raise Vimscript error message after removing existing message prefixes
M.notify_vim_error = function(msg, lvl)
  M.notify(msg:gsub("^Vim:", ""):gsub("^gitlab.nvim: ", ""), lvl)
end

M.get_current_line_number = function()
  return vim.api.nvim_call_function("line", { "." })
end

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

M.get_buffer_text = function(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return ""
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local text = table.concat(lines, "\n")
  return text
end

---Returns the number of lines in the buffer. Returns 1 even for empty buffers.
M.get_buffer_length = function(bufnr)
  return #vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
end

---Convert string to corresponding boolean
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

---Convert boolean to corresponding string
---@param bool boolean
---@return string
M.bool_to_string = function(bool)
  if bool == true then
    return "true"
  end
  return "false"
end

---Toggle boolean value
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
  bool = bool:gsub("^%s+", ""):gsub("%s+$", "")
  local toggled = string_bools[bool]
  if toggled == nil then
    M.notify(("Cannot toggle value '%s'"):format(bool), vim.log.levels.ERROR)
    return bool
  end
  return toggled
end

M.string_starts = function(str, start)
  return str:sub(1, #start) == start
end

M.press_enter = function()
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", false, true, true), "n", false)
end

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

M.format_date = function(date_string)
  local date_table = os.date("!*t")
  local date = M.from_iso_format_date_to_timestamp(date_string)

  local current_date = os.time({
    year = date_table.year,
    month = date_table.month,
    day = date_table.day,
    hour = date_table.hour,
    min = date_table.min,
    sec = date_table.sec,
  })

  local time_diff = current_date - date

  if time_diff < 60 then
    return M.pluralize(time_diff, "second")
  elseif time_diff < 3600 then
    return M.pluralize(math.floor(time_diff / 60), "minute")
  elseif time_diff < 86400 then
    return M.pluralize(math.floor(time_diff / 3600), "hour")
  elseif time_diff < 2592000 then
    return M.pluralize(math.floor(time_diff / 86400), "day")
  else
    local formatted_date = os.date("%A, %B %e", date)
    return formatted_date
  end
end

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

M.current_file_path = function()
  local path = debug.getinfo(1, "S").source:sub(2)
  return vim.fn.fnamemodify(path, ":p")
end

local random = math.random
M.uuid = function()
  local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
  return string.gsub(template, "[xy]", function(c)
    local v = (c == "x") and random(0, 0xf) or random(8, 0xb)
    return string.format("%x", v)
  end)
end

M.remove_last_chunk = function(sentence)
  local words = {}
  for word in sentence:gmatch("%S+") do
    table.insert(words, word)
  end
  table.remove(words, #words)
  local sentence_without_last = table.concat(words, " ")
  return sentence_without_last
end

M.get_line_content = function(bufnr, start)
  local current_buffer = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr ~= nil and bufnr or current_buffer, start - 1, start, false)
  return lines[1]
end

M.switch_can_edit_buf = function(buf, bool)
  vim.api.nvim_set_option_value("modifiable", bool, { buf = buf })
  vim.api.nvim_set_option_value("readonly", not bool, { buf = buf })
end

-- Gets the window holding a buffer in the current tab page
---@param buffer_id number Id of a buffer
---@return integer|nil
M.get_window_id_by_buffer_id = function(buffer_id)
  local tabpage = vim.api.nvim_get_current_tabpage()
  local windows = vim.api.nvim_tabpage_list_wins(tabpage)

  return List.new(windows):find(function(win_id)
    local buf_id = vim.api.nvim_win_get_buf(win_id)
    return buf_id == buffer_id
  end)
end

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

---Check if current mode is visual mode
---@return boolean is_visual true if current mode is visual mode
M.check_visual_mode = function()
  local mode = vim.api.nvim_get_mode().mode
  if mode ~= "v" and mode ~= "V" then
    M.notify("Code suggestions and multiline comments are only available in visual mode", vim.log.levels.WARN)
    return false
  end
  return true
end

---Return start line and end line of visual selection.
---Exists visual mode in order to access marks "<" , ">"
---@return integer start,integer end Start line and end line
M.get_visual_selection_boundaries = function()
  M.press_escape()
  local start_line = vim.api.nvim_buf_get_mark(0, "<")[1]
  local end_line = vim.api.nvim_buf_get_mark(0, ">")[1]
  return start_line, end_line
end

---Get icon for filename if nvim-web-devicons plugin is available otherwise return empty string
---@return string?
---@return string?
M.get_icon = function(filename)
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

---Return content between start_line and end_line
---@param start_line integer
---@param end_line integer
---@return string[]
M.get_lines = function(start_line, end_line)
  return vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
end

M.make_comma_separated_readable = function(str)
  return string.gsub(str, ",", ", ")
end

---Select a git branch and perform callback with the branch as an argument
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

M.basename = function(str)
  local name = string.gsub(str, "(.*/)(.*)", "%2")
  return name
end

M.get_web_url = function()
  local web_url = require("gitlab.state").INFO.web_url
  if web_url ~= nil then
    return web_url
  end
  M.notify("Could not get Gitlab URL", vim.log.levels.ERROR)
end

---@param url string?
M.open_in_browser = function(url)
  if vim.fn.has("mac") == 1 then
    vim.fn.jobstart({ "open", url })
  elseif vim.fn.has("unix") == 1 then
    vim.fn.jobstart({ "xdg-open", url })
  else
    M.notify("Opening a Gitlab URL is not supported on this OS!", vim.log.levels.ERROR)
  end
end

---Combines two tables
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
---Trims the trailing slash from a URL
---@param s string
---@return string
M.trim_slash = function(s)
  return (s:gsub("/+$", ""))
end

M.ensure_table = function(data)
  if data == vim.NIL or data == nil then
    return {}
  end
  return data
end

M.get_nested_field = function(table, field)
  local subfield = string.match(field, "[^.]+")
  local subtable = table[subfield]
  if subtable ~= nil then
    local new_field = string.gsub(field, "^" .. subfield .. ".?", "")
    if new_field ~= "" then
      return M.get_nested_field(subtable, new_field)
    else
      return subtable
    end
  end
end

M.open_fold_under_cursor = function()
  if vim.fn.foldclosed(vim.fn.line(".")) > -1 then
    vim.cmd("normal! zo")
  end
end

return M
