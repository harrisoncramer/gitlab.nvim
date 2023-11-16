local Job                 = require("plenary.job")
local M                   = {}

M.notify                  = function(msg, lvl)
  vim.notify("gitlab.nvim: " .. msg, lvl)
end

M.get_colors_for_group    = function(group)
  local normal_fg = vim.fn.synIDattr(vim.fn.synIDtrans((vim.fn.hlID(group))), "fg")
  local normal_bg = vim.fn.synIDattr(vim.fn.synIDtrans((vim.fn.hlID(group))), "bg")
  return { fg = normal_fg, bg = normal_bg }
end

M.get_current_line_number = function()
  return vim.api.nvim_call_function("line", { "." })
end

M.is_windows              = function()
  if vim.fn.has("win32") == 1 or vim.fn.has("win32unix") == 1 then
    return true
  end
  return false
end

M.P                       = function(...)
  local objects = {}
  for i = 1, select("#", ...) do
    local v = select(i, ...)
    table.insert(objects, vim.inspect(v))
  end

  print(table.concat(objects, "\n"))
  return ...
end

M.get_buffer_text         = function(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local text = table.concat(lines, "\n")
  return text
end

M.string_starts           = function(str, start)
  return str:sub(1, #start) == start
end

M.press_enter             = function()
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", false, true, true), "n", false)
end

function offset_to_seconds(offset)
  local sign, hours, minutes = offset:match("([%+%-])(%d%d)(%d%d)")
  print(sign, hours, minutes)
  local offsetSeconds = tonumber(hours) * 3600 + tonumber(minutes) * 60
  if sign == "-" then
    offsetSeconds = -offsetSeconds
  end
  return offsetSeconds
end

M.format_to_local    = function(date_string)
  local year, month, day, hour, min, sec, _ms, tzOffset = date_string:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+).(%d+)Z")
  local localTime = os.time({
    year = year,
    month = month,
    day = day,
    hour = hour,
    min = min,
    sec = sec,
    tzOffset = tzOffset,
  })

  local offset = vim.fn.strftime("%z")
  local localTimestamp = localTime + offset_to_seconds(offset)

  return os.date("%m/%d/%Y at%l:%M %Z", localTimestamp)
end

M.format_date        = function(date_string)
  local date_table = os.date("!*t")
  local year, month, day, hour, min, sec = date_string:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
  local date = os.time({ year = year, month = month, day = day, hour = hour, min = min, sec = sec })

  local current_date = os.time({
    year = date_table.year,
    month = date_table.month,
    day = date_table.day,
    hour = date_table.hour,
    min = date_table.min,
    sec = date_table.sec,
  })

  local time_diff = current_date - date

  local function pluralize(num, word)
    return num .. string.format(" %s", word) .. (num > 1 and "s" or "") .. " ago"
  end

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

M.create_popup_state = function(title, width, height)
  return {
    buf_options = {
      filetype = "markdown",
    },
    relative = "editor",
    enter = true,
    focusable = true,
    border = {
      style = "rounded",
      text = {
        top = title,
      },
    },
    position = "50%",
    size = {
      width = width,
      height = height,
    },
  }
end

M.merge = function(defaults, overrides)
  if type(defaults) == "table" and M.table_size(defaults) == 0 and type(overrides) == "table" then
    return overrides
  end
  return vim.tbl_deep_extend("force", defaults, overrides)
end

M.join = function(tbl, separator)
  separator = separator or " "

  local result = ""
  for _, value in pairs(tbl) do
    result = result .. tostring(value) .. separator
  end

  -- Remove the trailing separator
  if separator ~= "" then
    result = result:sub(1, - #separator - 1)
  end

  return result
end

M.remove_first_value = function(tbl)
  local sliced_table = {}
  for i = 2, #tbl do
    table.insert(sliced_table, tbl[i])
  end

  return sliced_table
end

M.read_file = function(file_path)
  local file = io.open(file_path, "r")
  if file == nil then
    return nil
  end
  local file_contents = file:read("*all")
  file:close()
  file_contents = string.gsub(file_contents, "\n", "")
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

M.join_tables = function(table1, table2)
  for _, value in ipairs(table2) do
    table.insert(table1, value)
  end

  return table1
end

M.table_size = function(t)
  local count = 0
  for _ in pairs(t) do
    count = count + 1
  end
  return count
end

M.contains = function(array, search_value)
  for _, value in ipairs(array) do
    if value == search_value then
      return true
    end
  end
  return false
end

M.extract = function(t, property)
  local resultTable = {}
  for _, value in ipairs(t) do
    if value[property] then
      table.insert(resultTable, value[property])
    end
  end
  return resultTable
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

M.get_first_chunk = function(sentence, divider)
  local words = {}
  for word in sentence:gmatch(divider or "%S+") do
    table.insert(words, word)
  end
  return words[1]
end

M.get_last_chunk = function(sentence, divider)
  local words = {}
  for word in sentence:gmatch(divider or "%S+") do
    table.insert(words, word)
  end
  return words[#words]
end

M.trim = function(s)
  return s:gsub("^%s+", ""):gsub("%s+$", "")
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
      local file_path = folder_path .. (M.is_windows() and "\\" or "/") .. file
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

M.reverse = function(list)
  local rev = {}
  for i = #list, 1, -1 do
    rev[#rev + 1] = list[i]
  end
  return rev
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
---@return boolean true if current mode is visual mode
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
---@return integer,integer start line and end line
M.get_visual_selection_boundaries = function()
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", false, true, true), "nx", false)
  local start_line = vim.api.nvim_buf_get_mark(0, "<")[1]
  local end_line = vim.api.nvim_buf_get_mark(0, ">")[1]
  return start_line, end_line
end

return M
