-- This Module contains all of the code specific to the Diffview reviewer.
local u = require("gitlab.utils")
local state = require("gitlab.state")
local async_ok, async = pcall(require, "diffview.async")

local M = {
  bufnr = nil,
  tabnr = nil,
}

-- Public Functions
-- These functions are exposed externally and are used
-- when the reviewer is consumed by other code. They must follow the specification
-- outlined in the reviewer/init.lua file
M.open = function()
  vim.api.nvim_command(string.format("DiffviewOpen %s", state.INFO.target_branch))
  M.tabnr = vim.api.nvim_get_current_tabpage()
end

M.jump = function(file_name, new_line, old_line)
  if M.tabnr == nil then
    vim.notify("Can't jump to Diffvew. Is it open?", vim.log.levels.ERROR)
    return
  end
  vim.api.nvim_set_current_tabpage(M.tabnr)
  vim.cmd("DiffviewFocusFiles")
  local view = require("diffview.lib").get_current_view()
  if view == nil then
    vim.notify("Could not find Diffview view", vim.log.levels.ERROR)
    return
  end
  local files = view.panel:ordered_file_list()
  local layout = view.cur_layout
  for _, file in ipairs(files) do
    if file.path == file_name then
      if not async_ok then
        vim.notify("Could not load Diffview async", vim.log.levels.ERROR)
        return
      end
      async.await(view:set_file(file))
      if new_line ~= nil then
        layout.b:focus()
        vim.api.nvim_win_set_cursor(0, { tonumber(new_line), 0 })
      elseif old_line ~= nil then
        layout.a:focus()
        vim.api.nvim_win_set_cursor(0, { tonumber(old_line), 0 })
      end
      break
    end
  end
end

---Get the location of a line within the diffview. If range is specified, then also the location
---of the lines in range.
---@param range LineRange | nil Line range to get location for
---@return ReviewerInfo | nil nil is returned only if error was encountered
M.get_location = function(range)
  if M.tabnr == nil then
    vim.notify("Diffview reviewer must be initialized first")
    return
  end
  local bufnr = vim.api.nvim_get_current_buf()
  local current_line = vim.api.nvim_win_get_cursor(0)[1]

  -- check if we are in the diffview tab
  local tabnr = vim.api.nvim_get_current_tabpage()
  if tabnr ~= M.tabnr then
    vim.notify("Line location can only be determined within reviewer window")
    return
  end

  -- check if we are in the diffview buffer
  local view = require("diffview.lib").get_current_view()
  if view == nil then
    vim.notify("Could not find Diffview view", vim.log.levels.ERROR)
    return
  end
  local layout = view.cur_layout
  local result = {}
  local type
  local is_new
  if layout.a.file.bufnr == bufnr then
    result.file_name = layout.a.file.path
    result.old_line = current_line
    type = "old"
    is_new = false
  elseif layout.b.file.bufnr == bufnr then
    result.file_name = layout.b.file.path
    result.new_line = current_line
    type = "new"
    is_new = true
  else
    vim.notify("Line location can only be determined within reviewer window")
    return
  end

  local hunks = u.parse_hunk_headers(result.file_name, state.INFO.target_branch)
  if hunks == nil then
    vim.notify("Could not parse hunks", vim.log.levels.ERROR)
    return
  end

  local current_line_info
  if is_new then
    current_line_info = u.get_lines_from_hunks(hunks, result.new_line, is_new)
  else
    current_line_info = u.get_lines_from_hunks(hunks, result.old_line, is_new)
  end

  -- If single line comment is outside of changed lines then we need to specify both new line and old line
  -- otherwise the API returns error.
  -- https://docs.gitlab.com/ee/api/discussions.html#create-a-new-thread-in-the-merge-request-diff
  if not current_line_info.in_hunk then
    result.old_line = current_line_info.old_line
    result.new_line = current_line_info.new_line
  end

  if range == nil then
    return result
  end

  result.range_info = { start = {}, ["end"] = {} }
  if current_line == range.start_line then
    result.range_info.start.old_line = current_line_info.old_line
    result.range_info.start.new_line = current_line_info.new_line
    result.range_info.start.type = type
  else
    local start_line_info = u.get_lines_from_hunks(hunks, range.start_line, is_new)
    result.range_info.start.old_line = start_line_info.old_line
    result.range_info.start.new_line = start_line_info.new_line
    result.range_info.start.type = type
  end

  if current_line == range.end_line then
    result.range_info["end"].old_line = current_line_info.old_line
    result.range_info["end"].new_line = current_line_info.new_line
    result.range_info["end"].type = type
  else
    local end_line_info = u.get_lines_from_hunks(hunks, range.end_line, is_new)
    result.range_info["end"].old_line = end_line_info.old_line
    result.range_info["end"].new_line = end_line_info.new_line
    result.range_info["end"].type = type
  end

  return result
end

---Return content between start_line and end_line
---@param start_line integer
---@param end_line integer
---@return string[]
M.get_lines = function(start_line, end_line)
  return vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
end

return M
