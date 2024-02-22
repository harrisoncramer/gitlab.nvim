local u = require("gitlab.utils")
local state = require("gitlab.state")
local hunks = require("gitlab.hunks")
local M = {}

---Takes in information about the current changes, such as the file name, modification type of the diff, and the line numbers
---and builds the appropriate payload when creating a comment.
---@param current_file string
---@param modification_type string
---@param file_name string
---@param old_line number
---@param new_line number
---@param visual_range LineRange | nil
M.build_location_data = function(current_file, modification_type, file_name, old_line, new_line, visual_range)
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
    payload.new_line = new_line
    -- Comment on deleted line: Include only old_line in payload.
  elseif modification_type == "deleted" then
    payload.old_line = old_line
    payload.new_line = nil
    -- The line was not found in any hunks, send both lines.
  elseif modification_type == "unmodified" or modification_type == "bad_file_unmodified" then
    payload.old_line = old_line
    payload.new_line = new_line
  end

  if visual_range == nil then
    return payload
  end

  local start_range_info = M.get_start_range(visual_range)
  local end_range_info = M.get_end_range(visual_range)

  -- Failed to get range
  if start_range_info == nil or end_range_info == nil then
    return nil
  end

  payload.range_info = {
    start = {
      old_line = start_range_info.old_line,
      new_line = start_range_info.new_line,
      type = start_range_info.type,
    },
    ["end"] = {
      old_line = end_range_info.old_line,
      new_line = end_range_info.new_line,
      type = end_range_info.type,
    },
  }

  return payload
end

-- Returns the matching line from the new SHA.
-- For instance, line 12 in the new SHA may be scroll-linked
-- to line 10 in the old SHA.
---@param line number
---@param offset number
---@return number|nil
local get_line_number_from_new_sha = function(line, offset)
  local reviewer = require("gitlab.reviewer")
  local is_current_sha = reviewer.is_current_sha()
  if is_current_sha then
    return line
  end
  local matching_line = reviewer.get_matching_line() - offset
  return matching_line
end

-- Returns the matching line from the old SHA.
-- For instance, line 12 in the new SHA may be scroll-linked
-- to line 10 in the old SHA.
---@param line number
---@param offset number
---@return number|nil
local get_line_number_from_old_sha = function(line, offset)
  local reviewer = require("gitlab.reviewer")
  local is_current_sha = reviewer.is_current_sha()
  if not is_current_sha then
    return line
  end
  local matching_line = reviewer.get_matching_line() - offset
  return matching_line
end

-- Given a new_line and old_line from the start of a ranged comment, returns the start
-- range information for the Gitlab payload
---@param visual_range LineRange
---@return ReviewerLineInfo|nil
M.get_start_range = function(visual_range)
  local current_file = require("gitlab.reviewer.diffview").get_current_file()
  if current_file == nil then
    u.notify("Error retrieving current file from Diffview", vim.log.levels.ERROR)
    return
  end

  local reviewer = require("gitlab.reviewer")
  local win_id = reviewer.is_current_sha() and reviewer.get_winnr_of_new_sha() or reviewer.get_winnr_of_old_sha()
  if win_id == nil then
    u.notify("Error getting bufnr of SHA for start range", vim.log.levels.ERROR)
    return
  end

  local current_line = vim.api.nvim_win_get_cursor(win_id)[1]
  local offset = current_line - visual_range.start_line

  local new_line = get_line_number_from_new_sha(visual_range.start_line, offset)
  local old_line = get_line_number_from_old_sha(visual_range.start_line, offset)
  if new_line == nil or old_line == nil then
    u.notify("Error getting new or old line for start range", vim.log.levels.ERROR)
    return
  end

  local modification_type = hunks.get_modification_type(old_line, new_line, current_file)

  return {
    new_line = new_line,
    old_line = old_line,
    type = modification_type == "added" and "new" or "old"
  }
end

-- Given a modification type, a range, and the hunk data, returns the end range information
-- for the Gitlab payload
---@param visual_range LineRange
---@return ReviewerLineInfo|nil
M.get_end_range = function(visual_range)
  local current_file = require("gitlab.reviewer.diffview").get_current_file()
  if current_file == nil then
    u.notify("Error retrieving current file from Diffview", vim.log.levels.ERROR)
    return
  end

  -- local current_line = vim.api.nvim_win_get_cursor(0)[0]
  -- local offset = current_line - visual_range.start_line

  local new_line = get_line_number_from_new_sha(visual_range.end_line, 0)
  local old_line = get_line_number_from_old_sha(visual_range.end_line, 0)

  if new_line == nil or old_line == nil then
    u.notify("Error getting new or old line for end range", vim.log.levels.ERROR)
    return
  end

  local modification_type = hunks.get_modification_type(old_line, new_line, current_file)
  return {
    new_line = new_line,
    old_line = old_line,
    type = modification_type == "added" and "new" or "old"
  }
end

return M
