-- This Module contains all of the code specific to the Delta reviewer.
local state = require("gitlab.state")
local u = require("gitlab.utils")

local M = {
  bufnr = nil,
}

-- Public Functions
-- These functions are exposed externally and are used
-- when the reviewer is consumed by other code. They must follow the specification
-- outlined in the reviewer/init.lua file
M.open = function()
  local current_buf = vim.api.nvim_get_current_buf()
  if current_buf == state.discussion_buf then
    vim.api.nvim_command("wincmd w")
  end

  vim.cmd.enew()
  if M.bufnr ~= nil then
    vim.api.nvim_set_current_buf(M.bufnr)
    return
  end

  local term_command_template =
    "GIT_PAGER='delta --hunk-header-style omit --line-numbers --paging never --file-added-label %s --file-removed-label %s --file-modified-label %s' git diff %s...HEAD"

  local term_command = string.format(
    term_command_template,
    state.settings.review_pane.delta.added_file,
    state.settings.review_pane.delta.removed_file,
    state.settings.review_pane.delta.modified_file,
    state.INFO.target_branch
  )

  vim.fn.termopen(term_command) -- Calls delta and sends the output to the currently blank buffer
  M.bufnr = vim.api.nvim_get_current_buf()
  M.winnr = vim.api.nvim_get_current_win()
end

M.jump = function(file_name, new_line, old_line)
  local linnr, error = M.get_jump_location(file_name, new_line, old_line)
  if error ~= nil then
    vim.notify(error, vim.log.levels.ERROR)
    return
  end

  vim.api.nvim_set_current_win(M.winnr)
  u.jump_to_buffer(M.bufnr, linnr)
end

---Get the location of a line within the delta buffer. If range is specified, then also the location
---of the lines in range.
---@param range LineRange | nil Line range to get location for
---@return ReviewerInfo | nil nil is returned only if error was encountered
M.get_location = function(range)
  if M.bufnr == nil then
    vim.notify("Delta reviewer must be initialized first", vim.log.levels.ERROR)
    return
  end

  if range then
    vim.notify("Multiline comments are not yet supported for delta reviewer", vim.log.levels.ERROR)
    return
  end

  local bufnr = vim.api.nvim_get_current_buf()
  if bufnr ~= M.bufnr then
    vim.notify("Line location can only be determined within reviewer window")
    return
  end

  local line_num = u.get_current_line_number()
  local file_name = M.get_file_from_review_buffer(u.get_current_line_number())

  local review_range, error = M.get_review_buffer_range(file_name)

  if error ~= nil then
    vim.notify(error, vim.log.levels.ERROR)
    return
  end

  if review_range == nil then
    vim.notify("Review buffer range could not be identified", vim.log.levels.ERROR)
    return
  end

  -- In case the comment is left on a line without change information, we
  -- iterate backward until we find it within the range of the changes
  local current_line_changes = nil
  local num = line_num
  while review_range ~= nil and num >= review_range[1] and current_line_changes == nil do
    local content = u.get_line_content(M.bufnr, num)
    local change_nums = M.get_change_nums(content)
    current_line_changes = change_nums
    num = num - 1
  end

  if current_line_changes == nil then
    vim.notify("Could not find current line change information", vim.log.levels.ERROR)
    return
  end

  local new_line_num = line_num + 1
  local next_line_changes = nil
  while review_range ~= nil and new_line_num <= review_range[2] and next_line_changes == nil do
    local content = u.get_line_content(M.bufnr, new_line_num)
    local change_nums = M.get_change_nums(content)
    next_line_changes = change_nums
    new_line_num = new_line_num + 1
  end

  if next_line_changes == nil then
    vim.notify("Could not find next line change information", vim.log.levels.ERROR)
    return
  end

  local result = { file_name = file_name }
  -- This is actually a modified line if these conditions are met
  if
    current_line_changes.old_line
    and not current_line_changes.new_line
    and not next_line_changes.old_line
    and next_line_changes.new_line
  then
    result.old_line = current_line_changes.old
    result.new_line = next_line_changes.new_line
  else
    vim.notify("Could not determine line location", vim.log.levels.ERROR)
    return
  end

  return result
end

-- Helper Functions 🤝
-- These functions are not exported and should be private
-- to the delta reviewer, they are used to support the public functions
M.get_jump_location = function(file_name, new_line, old_line)
  local range, error = M.get_review_buffer_range(file_name)
  if error ~= nil then
    return nil, error
  end
  if range == nil then
    return nil, "Review buffer range could not be identified"
  end

  local linnr = nil

  local lines = M.get_review_buffer_lines(range)
  for _, line in ipairs(lines) do
    local line_data = M.get_change_nums(line.line_content)
    if line_data and old_line == line_data.old_line and new_line == line_data.new_line then
      linnr = line.line_number
      break
    end
  end
  if linnr == nil then
    return nil, "Could not find matching line"
  end
  return linnr, nil
end

M.get_file_from_review_buffer = function(linenr)
  for i = linenr, 0, -1 do
    local line_content = u.get_line_content(M.bufnr, i)
    if M.starts_with_file_symbol(line_content) then
      local file_name = u.get_last_chunk(line_content)
      return file_name
    end
  end
end

M.get_change_nums = function(line)
  local data, _ = line:match("(.-)" .. "│" .. "(.*)")
  local line_data = {}
  if data == nil then
    return nil
  end

  if data ~= nil and data ~= "" then
    local old_line = u.trim(u.get_first_chunk(data, "[^" .. "⋮" .. "]+"))
    local new_line = u.trim(u.get_last_chunk(data, "[^" .. "⋮" .. "]+"))
    line_data.new_line = tonumber(new_line)
    line_data.old_line = tonumber(old_line)
  end

  if line_data.new_line == nil and line_data.old_line == nil then
    return nil
  end

  return line_data
end

M.get_review_buffer_range = function(file_name)
  if M.bufnr == nil then
    return nil, "Delta reviewer must be initialized first"
  end
  local lines = vim.api.nvim_buf_get_lines(M.bufnr, 0, -1, false)
  local start = nil
  local stop = nil

  for i, line in ipairs(lines) do
    if start ~= nil and stop ~= nil then
      return { start, stop }
    end
    if M.starts_with_file_symbol(line) then
      -- Check if the file name matches the node name
      local delta_file_name = u.get_last_chunk(line)
      if file_name == delta_file_name then
        start = i
      elseif start ~= nil then
        stop = i
      end
    end
  end

  -- We've reached the end of the file, set "stop" in case we already found start
  stop = #lines
  if start ~= nil and stop ~= nil then
    return { start, stop }
  end
end

M.starts_with_file_symbol = function(line)
  for _, substring in ipairs({
    state.settings.review_pane.delta.added_file,
    state.settings.review_pane.delta.removed_file,
    state.settings.review_pane.delta.modified_file,
  }) do
    if string.sub(line, 1, string.len(substring)) == substring then
      return true
    end
  end
  return false
end

M.get_review_buffer_lines = function(review_buffer_range)
  local lines = {}
  for i = review_buffer_range[1], review_buffer_range[2], 1 do
    local line_content = vim.api.nvim_buf_get_lines(M.bufnr, i - 1, i, false)[1]
    if string.find(line_content, "⋮") then
      table.insert(lines, { line_content = line_content, line_number = i })
    end
  end
  return lines
end

---Return content between start_line and end_line
---@param start_line integer
---@param end_line integer
---@return string[] | nil
M.get_lines = function(start_line, end_line)
  vim.notify("Getting lines in delta is not supported yet", vim.log.levels.ERROR)
  return nil
end
return M
