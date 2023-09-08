local M = {}

M.get_current_line_number = function()
  return vim.api.nvim_call_function('line', { '.' })
end

M.has_reviewer = function(reviewer)
  local has_reviewer = false
  if reviewer == "diffview" then
    has_reviewer = vim.fn.exists(":DiffviewOpen") ~= 0
  else
    has_reviewer = vim.fn.executable("delta") == 1
  end

  if not has_reviewer then
    error(string.format("Please install %s or change your reviewer", reviewer))
  end

  return has_reviewer
end

M.is_windows = function()
  if vim.fn.has("win32") == 1 or vim.fn.has("win32unix") == 1 then
    return true
  end
  return false
end

M.P = function(...)
  local objects = {}
  for i = 1, select("#", ...) do
    local v = select(i, ...)
    table.insert(objects, vim.inspect(v))
  end

  print(table.concat(objects, "\n"))
  return ...
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

M.format_date = function(date_string)
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

  local function pluralize(num, word)
    return num .. string.format(" %s", word) .. (num > 1 and "s" or '') .. " ago"
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

M.jump_to_file = function(filename, line_number)
  if line_number == nil then line_number = 1 end
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

M.merge = function(defaults, overrides)
  local result = {}
  if type(defaults) == "table" and M.table_size(defaults) == 0 and type(overrides) == "table" then
    return overrides
  end

  for key, value in pairs(defaults) do
    if type(value) == "table" then
      result[key] = M.merge(value, overrides[key] or {})
    else
      result[key] = overrides[key] or value
    end
  end

  return result
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
  local path = debug.getinfo(1, 'S').source:sub(2)
  return vim.fn.fnamemodify(path, ':p')
end

local random = math.random
M.uuid = function()
  local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
  return string.gsub(template, '[xy]', function(c)
    local v = (c == 'x') and random(0, 0xf) or random(8, 0xb)
    return string.format('%x', v)
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
  for _ in pairs(t) do count = count + 1 end
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
  local lines = vim.api.nvim_buf_get_lines(
    bufnr ~= nil and bufnr or current_buffer,
    start - 1,
    start,
    false)

  for _, line in ipairs(lines) do
    return line
  end
end

M.get_win_from_buf = function(bufnr)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.fn.winbufnr(win) == bufnr then
      return win
    end
  end
end

M.switch_can_edit_buf = function(buf, bool)
  vim.api.nvim_buf_set_option(buf, 'modifiable', bool)
  vim.api.nvim_buf_set_option(buf, "readonly", not bool)
end

M.list_files_in_folder = function(folder_path)
  if vim.fn.isdirectory(folder_path) == 0 then
    return nil
  end

  local folder_ok, folder = pcall(vim.fn.readdir, folder_path)

  if not folder_ok then return nil end

  local files = {}
  if folder ~= nil then
    for _, file in ipairs(folder) do
      local file_path = folder_path .. (M.is_windows() and "\\" or '/') .. file
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

return M
