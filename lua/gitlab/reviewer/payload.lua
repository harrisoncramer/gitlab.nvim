local state     = require("gitlab.state")
local u         = require("gitlab.utils")
local hunks     = require("gitlab.hunks")
local M         = {}

---Takes in information about the current changes, such as the file name, modification type of the diff, and the line numbers
---and builds the appropriate payload when creating a comment.
---@param current_file string
---@param modification_type string
---@param file_name string
---@param a_linenr number
---@param b_linenr number
M.build_payload = function(current_file, modification_type, file_name, a_linenr, b_linenr, range)
  local data = hunks.parse_hunks_and_diff(current_file, state.INFO.target_branch)

  ---@type ReviewerInfo
  local payload = {
    file_name = file_name,
    new_line = nil,
    old_line = nil,
    range_info = nil,
  }

  -- Comment on new line: Include only new_line in payload.
  if modification_type == "added" then
    payload.old_line = nil
    payload.new_line = b_linenr
    -- Comment on deleted line: Include only new_line in payload.
  elseif modification_type == "deleted" then
    payload.old_line = a_linenr
    payload.new_line = nil
    -- The line was not found in any hunks, only send the old line number
  elseif modification_type == "unmodified" or modification_type == "bad_file_unmodified" then
    payload.old_line = a_linenr
    payload.new_line = b_linenr
  end

  if range == nil then
    return payload
  end

  -- If there's a range, use the start of the visual selection, not the current line
  local current_line = range and range.start_line or vim.api.nvim_win_get_cursor(0)[1]

  -- If leaving a multi-line comment, we want to also add range_info to the payload.
  local is_new = payload.new_line ~= nil
  local current_line_info = is_new and hunks.get_lines_from_hunks(data.hunks, payload.new_line, is_new) or
      hunks.get_lines_from_hunks(data.hunks, payload.old_line, is_new)
  local type = is_new and "new" or "old"

  ---@type ReviewerRangeInfo
  local range_info = { start = {},["end"] = {} }

  if current_line == range.start_line then
    range_info.start.old_line = current_line_info.old_line
    range_info.start.new_line = current_line_info.new_line
    range_info.start.type = type
  else
    local start_line_info = hunks.get_lines_from_hunks(data.hunks, range.start_line, is_new)
    range_info.start.old_line = start_line_info.old_line
    range_info.start.new_line = start_line_info.new_line
    range_info.start.type = type
  end
  if current_line == range.end_line then
    range_info["end"].old_line = current_line_info.old_line
    range_info["end"].new_line = current_line_info.new_line
    range_info["end"].type = type
  else
    local end_line_info = hunks.get_lines_from_hunks(data.hunks, range.end_line, is_new)
    range_info["end"].old_line = end_line_info.old_line
    range_info["end"].new_line = end_line_info.new_line
    range_info["end"].type = type
  end

  payload.range_info = range_info

  return payload
end

return M
