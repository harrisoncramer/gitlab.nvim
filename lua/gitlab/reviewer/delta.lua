local state                   = require("gitlab.state")
local u                       = require("gitlab.utils")

-- Work in progress refactor: This Module contains all of the code
-- specific to the Delta reviewer

local M                       = {
  bufnr = nil
}

M.open                        = function()
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
  "GIT_PAGER='delta --hunk-header-style omit --line-numbers --paging never --file-added-label %s --file-removed-label %s --file-modified-label %s' git diff --cached %s"

  local term_command = string.format(term_command_template,
    state.settings.review_pane.added_file,
    state.settings.review_pane.removed_file,
    state.settings.review_pane.modified_file,
    state.INFO.target_branch)

  vim.fn.termopen(term_command) -- Calls delta and sends the output to the currently blank buffer
  M.bufnr = vim.api.nvim_get_current_buf()
end

M.jump                        = function(file_name, new_line, old_line)
  local linnr, error = M.get_jump_location(file_name, new_line, old_line)
  if error ~= nil then
    vim.notify(error, vim.log.levels.ERROR)
    return
  end

  vim.api.nvim_command("wincmd w")
  u.jump_to_buffer(M.bufnr, linnr)
end

-- TODO: Jump back to discussion tree
M.get_jump_location           = function(file_name, new_line, old_line)
  local range, error = M.get_review_buffer_range(file_name)
  if error ~= nil then return nil, error end
  if range == nil then return nil, "Review buffer range could not be identified" end

  local linnr = nil

  local lines = M.get_review_buffer_lines(range)
  for _, line in ipairs(lines) do
    local line_data = M.get_change_nums(line.line_content)
    if old_line == line_data.old_line and new_line == line_data.new_line then
      linnr = line.line_number
      break
    end
  end
  if linnr == nil then return nil, "Could not find matching line" end
  return linnr, nil
end

M.get_location                = function()
  local line_num = u.get_current_line_number()
  local content = u.get_line_content(M.bufnr, line_num)
  local current_line_changes = M.get_change_nums(content)
  local new_line = u.get_line_content(M.bufnr, line_num + 1)
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
    return nil, nil, "Cannot comment on invalid line"
  end

  local file_name = M.get_file_from_review_buffer(u.get_current_line_number())

  return file_name, current_line_changes
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


M.get_review_buffer_range = function(file_name)
  if M.bufnr == nil then return nil, "Delta reviewer must be initialized first" end
  local lines = vim.api.nvim_buf_get_lines(M.bufnr, 0, -1, false)
  local start = nil
  local stop = nil

  for i, line in ipairs(lines) do
    if start ~= nil and stop ~= nil then return { start, stop } end
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
  if start ~= nil and stop ~= nil then return { start, stop } end
end

M.starts_with_file_symbol = function(line)
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

return M
