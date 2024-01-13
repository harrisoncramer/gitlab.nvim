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

M.filter = function(input_table, value_to_remove)
  local resultTable = {}
  for _, v in ipairs(input_table) do
    if v ~= value_to_remove then
      table.insert(resultTable, v)
    end
  end
  return resultTable
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

---Pluralizes the input word, e.g. "3 cows"
---@param num integer The count of the item/word
---@param word string The word to pluralize
---@return string
local function pluralize(num, word)
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
    return pluralize(time_diff, "second") .. " ago"
  elseif time_diff < 3600 then
    return pluralize(math.floor(time_diff / 60), "minute") .. " ago"
  elseif time_diff < 86400 then
    return pluralize(math.floor(time_diff / 3600), "hour") .. " ago"
  elseif time_diff < 2592000 then
    return pluralize(math.floor(time_diff / 86400), "day") .. " ago"
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

M.get_colors_for_group = function(group)
  local normal_fg = vim.fn.synIDattr(vim.fn.synIDtrans((vim.fn.hlID(group))), "fg")
  local normal_bg = vim.fn.synIDattr(vim.fn.synIDtrans((vim.fn.hlID(group))), "bg")
  return { fg = normal_fg, bg = normal_bg }
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
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local text = table.concat(lines, "\n")
  return text
end

M.string_starts = function(str, start)
  return str:sub(1, #start) == start
end

M.press_enter = function()
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", false, true, true), "n", false)
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
    return pluralize(time_diff, "second")
  elseif time_diff < 3600 then
    return pluralize(math.floor(time_diff / 60), "minute")
  elseif time_diff < 86400 then
    return pluralize(math.floor(time_diff / 3600), "hour")
  elseif time_diff < 2592000 then
    return pluralize(math.floor(time_diff / 86400), "day")
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

M.jump_to_file = function(filename, line_number)
  if line_number == nil then
    line_number = 1
  end
  local bufnr = vim.fn.bufnr(filename)
  if bufnr ~= -1 then
    M.jump_to_buffer(bufnr, line_number)
    return
  end

  -- If buffer is not already open, open it
  vim.cmd("edit " .. filename)
  vim.api.nvim_win_set_cursor(0, { line_number, 0 })
end

M.jump_to_buffer = function(bufnr, line_number)
  vim.cmd("buffer " .. bufnr)
  vim.api.nvim_win_set_cursor(0, { line_number, 0 })
end

---Get the popup view_opts
---@param title string The string to appear on top of the popup
---@param settings table User defined popup settings
---@param width number? Override default width
---@param height number? Override default height
---@return table
M.create_popup_state = function(title, settings, width, height, zindex)
  local default_settings = require("gitlab.state").settings.popup
  local user_settings = settings or {}
  local view_opts = {
    buf_options = {
      filetype = "markdown",
    },
    relative = "editor",
    enter = true,
    focusable = true,
    zindex = zindex or 50,
    border = {
      style = user_settings.border or default_settings.border,
      text = {
        top = title,
      },
    },
    position = "50%",
    size = {
      width = user_settings.width or width or default_settings.width,
      height = user_settings.height or height or default_settings.height,
    },
    opacity = user_settings.opacity or default_settings.opacity,
  }

  return view_opts
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

M.get_win_from_buf = function(bufnr)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.fn.winbufnr(win) == bufnr then
      return win
    end
  end
end

M.switch_can_edit_buf = function(buf, bool)
  vim.api.nvim_set_option_value("modifiable", bool, { buf = buf })
  vim.api.nvim_set_option_value("readonly", not bool, { buf = buf })
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
    for _, file in ipairs(folder) do
      local file_path = folder_path .. M.path_separator .. file
      local timestamp = vim.fn.getftime(file_path)
      table.insert(files, { name = file, timestamp = timestamp })
    end
  end

  -- Sort the table by timestamp in descending order (newest first)
  table.sort(files, function(a, b)
    return a.timestamp > b.timestamp
  end)

  local result = {}
  for _, file in ipairs(files) do
    table.insert(result, file.name)
  end

  return result
end

---@class Hunk
---@field old_line integer
---@field old_range integer
---@field new_line integer
---@field new_range integer

---Parse git diff hunks.
---@param file_path string Path to file.
---@param base_branch string Git base branch of merge request.
---@return Hunk[] list of hunks.
M.parse_hunk_headers = function(file_path, base_branch)
  local hunks = {}

  local Job = require("plenary.job")

  local diff_job = Job:new({
    command = "git",
    args = { "diff", "--minimal", "--unified=0", "--no-color", base_branch, "--", file_path },
    on_exit = function(j, return_code)
      if return_code == 0 then
        for _, line in ipairs(j:result()) do
          if line:sub(1, 2) == "@@" then
            -- match:
            --  @@ -23 +23 @@ ...
            --  @@ -23,0 +23 @@ ...
            --  @@ -41,0 +42,4 @@ ...
            local old_start, old_range, new_start, new_range = line:match("@@+ %-(%d+),?(%d*) %+(%d+),?(%d*) @@+")

            table.insert(hunks, {
              old_line = tonumber(old_start),
              old_range = tonumber(old_range) or 0,
              new_line = tonumber(new_start),
              new_range = tonumber(new_range) or 0,
            })
          end
        end
      else
        M.notify("Failed to get git diff: " .. j:stderr(), vim.log.levels.WARN)
      end
    end,
  })

  diff_job:sync()

  return hunks
end

---@class LineDiffInfo
---@field old_line integer
---@field new_line integer
---@field in_hunk boolean

---Search git diff hunks to find old and new line number corresponding to target line.
---This function does not check if target line is outside of boundaries of file.
---@param hunks Hunk[] git diff parsed hunks.
---@param target_line integer line number to search for - based on is_new paramter the search is
---either in new lines or old lines of hunks.
---@param is_new boolean whether to search for new line or old line
---@return LineDiffInfo
M.get_lines_from_hunks = function(hunks, target_line, is_new)
  if #hunks == 0 then
    -- If there are zero hunks, return target_line for both old and new lines
    return { old_line = target_line, new_line = target_line, in_hunk = false }
  end
  local current_new_line = 0
  local current_old_line = 0
  if is_new then
    for _, hunk in ipairs(hunks) do
      -- target line is before current hunk
      if target_line < hunk.new_line then
        return {
          old_line = current_old_line + (target_line - current_new_line),
          new_line = target_line,
          in_hunk = false,
        }
        -- target line is within the current hunk
      elseif hunk.new_line <= target_line and target_line <= (hunk.new_line + hunk.new_range) then
        -- this is interesting magic of gitlab calculation
        return {
          old_line = hunk.old_line + hunk.old_range + 1,
          new_line = target_line,
          in_hunk = true,
        }
        -- target line is after the current hunk
      else
        current_new_line = hunk.new_line + hunk.new_range
        current_old_line = hunk.old_line + hunk.old_range
      end
    end
    -- target line is after last hunk
    return {
      old_line = current_old_line + (target_line - current_new_line),
      new_line = target_line,
      in_hunk = false,
    }
  else
    for _, hunk in ipairs(hunks) do
      -- target line is before current hunk
      if target_line < hunk.old_line then
        return {
          old_line = target_line,
          new_line = current_new_line + (target_line - current_old_line),
          in_hunk = false,
        }
        -- target line is within the current hunk
      elseif hunk.old_line <= target_line and target_line <= (hunk.old_line + hunk.old_range) then
        return {
          old_line = target_line,
          new_line = hunk.new_line,
          in_hunk = true,
        }
        -- target line is after the current hunk
      else
        current_new_line = hunk.new_line + hunk.new_range
        current_old_line = hunk.old_line + hunk.old_range
      end
    end
    -- target line is after last hunk
    return {
      old_line = current_old_line + (target_line - current_new_line),
      new_line = target_line,
      in_hunk = false,
    }
  end
end

---Check if current mode is visual mode
---@return boolean is_visual true if current mode is visual mode
M.check_visual_mode = function()
  local mode = vim.api.nvim_get_mode().mode
  if mode ~= "v" and mode ~= "V" then
    M.notify("Code suggestions are only available in visual mode", vim.log.levels.WARN)
    return false
  end
  return true
end

---Return start line and end line of visual selection.
---Exists visual mode in order to access marks "<" , ">"
---@return integer start,integer end Start line and end line
M.get_visual_selection_boundaries = function()
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", false, true, true), "nx", false)
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

M.make_comma_separated_readable = function(str)
  return string.gsub(str, ",", ", ")
end

---@param remote? boolean
M.get_all_git_branches = function(remote)
  local branches = {}

  local handle = remote == true and io.popen("git branch -r 2>&1") or io.popen("git branch 2>&1")

  if handle then
    for line in handle:lines() do
      local branch
      if remote then
        for res in line:gmatch("origin/([^\n]+)") do
          branch = res -- Trim /origin
        end
      else
        branch = line:gsub("^%s*%*?%s*", "") -- Trim leading whitespace and the "* " marker for the current branch
      end
      table.insert(branches, branch)
    end
    handle:close()
  else
    print("Error running 'git branch' command.")
  end

  return branches
end

M.basename = function(str)
  local name = string.gsub(str, "(.*/)(.*)", "%2")
  return name
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

return M
