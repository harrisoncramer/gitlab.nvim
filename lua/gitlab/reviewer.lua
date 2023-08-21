local state                   = require("gitlab.state")
local u                       = require("gitlab.utils")
local M                       = {}

M.get_changes                 = function()
  local line_num = u.get_current_line_number()
  local content = u.get_line_content(state.REVIEW_BUF, line_num)
  local current_line_changes = M.get_change_nums(content)
  local new_line = u.get_line_content(state.REVIEW_BUF, line_num + 1)
  local next_line_changes = M.get_change_nums(new_line)

  -- This is actually a modified line if these conditions are met
  if (current_line_changes.old_line and not current_line_changes.new_line and not next_line_changes.old_line and next_line_changes.new_line) then
    do
      current_line_changes = {
        old_line = current_line_changes.old,
        new_line = next_line_changes.new_line
      }
    end
  end

  local count = 0
  for _ in pairs(current_line_changes) do
    count = count + 1
  end

  if count == 0 then
    vim.notify("Cannot comment on invalid line", vim.log.levels.ERROR)
  end

  local file_name = M.get_file_from_review_buffer(u.get_current_line_number())

  return current_line_changes, file_name
end

M.get_file_from_review_buffer = function(linenr)
  for i = linenr, 0, -1 do
    local line_content = u.get_line_content(state.REVIEW_BUF, i)
    if M.starts_with_file_symbol(line_content) then
      local file_name = u.get_last_chunk(line_content)
      return file_name
    end
  end
end

M.get_change_nums             = function(line)
  local data, _ = line:match("(.-)" .. "│" .. "(.*)")
  local line_data = {}
  if data ~= nil then
    local old_line = u.trim(u.get_first_chunk(data, "[^" .. "⋮" .. "]+"))
    local new_line = u.trim(u.get_last_chunk(data, "[^" .. "⋮" .. "]+"))
    line_data.new_line = tonumber(new_line)
    line_data.old_line = tonumber(old_line)
  end
  return line_data
end

M.jump_to_location            = function(winnr, bufnr)
end

M.get_review_buffer_range     = function(node)
  local lines = vim.api.nvim_buf_get_lines(state.REVIEW_BUF, 0, -1, false)
  local start = nil
  local stop = nil

  for i, line in ipairs(lines) do
    if start ~= nil and stop ~= nil then return { start, stop } end
    if M.starts_with_file_symbol(line) then
      -- Check if the file name matches the node name
      local file_name = u.get_last_chunk(line)
      if file_name == node.file_name then
        start = i
      elseif start ~= nil then
        stop = i
      end
    end
  end

  -- We've reached the end of the file, set "stop" in case we already found start
  stop = #lines
  if start ~= nil and stop ~= nil then return { start, stop } end
end

M.starts_with_file_symbol     = function(line)
  for _, substring in ipairs({
    state.settings.review_pane.added_file,
    state.settings.review_pane.removed_file,
    state.settings.review_pane.modified_file,
  }) do
    if string.sub(line, 1, string.len(substring)) == substring then
      return true
    end
  end
  return false
end

M.get_review_buffer_lines     = function(review_buffer_range)
  local lines = {}
  for i = review_buffer_range[1], review_buffer_range[2], 1 do
    local line_content = vim.api.nvim_buf_get_lines(state.REVIEW_BUF, i - 1, i, false)[1]
    if string.find(line_content, "⋮") then
      table.insert(lines, { line_content = line_content, line_number = i })
    end
  end
  return lines
end

M.get_change_nums             = function(line)
  local data, _ = line:match("(.-)" .. "│" .. "(.*)")
  local line_data = {}
  if data ~= nil then
    local old_line = u.trim(u.get_first_chunk(data, "[^" .. "⋮" .. "]+"))
    local new_line = u.trim(u.get_last_chunk(data, "[^" .. "⋮" .. "]+"))
    line_data.new_line = tonumber(new_line)
    line_data.old_line = tonumber(old_line)
  end
  return line_data
end


return M
