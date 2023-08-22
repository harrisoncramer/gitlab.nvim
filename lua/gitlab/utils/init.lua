local M = {}

M.get_current_line_number = function()
  return vim.api.nvim_call_function('line', { '.' })
end

M.has_delta = function()
  return vim.fn.executable("delta") == 1
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

M.jump_to_location = function(filename, line_number)
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

return M
