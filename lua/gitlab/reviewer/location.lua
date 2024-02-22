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

  -- TODO: Assume visual range start is at top of block

  -- Assume at top of visual range in the new buffer...
  local start_range_info = M.get_start_range(visual_range, modification_type)
  local end_range_info = M.get_end_range(new_line, old_line, visual_range, current_file)

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

-- Returns the matching line from the other SHA (either old or new) based on
-- the line provided. For instance, line 12 in the new SHA may be scroll-linked
-- to line 10 in the old SHA.
---@param line number
---@param old_sha boolean
---@return number
M.get_matching_linenr = function(line, old_sha)
  local is_current_sha = require("gitlab.reviewer").is_current_sha()
  if (is_current_sha and not old_sha) or (not is_current_sha and old_sha) then
    return line
  end
  return 0 -- Get the line from the other SHA
end

-- Given a new_line and old_line from the start of a ranged comment, returns the start
-- range information for the Gitlab payload
---@param visual_range LineRange
---@param modification_type string
---@return ReviewerLineInfo
M.get_start_range = function(visual_range, modification_type)
  return {
    new_line = M.get_matching_linenr(visual_range.start_line, false),
    old_line = M.get_matching_linenr(visual_range.start_line, true),
    type = modification_type == "added" and "new" or "old"
  }
end

-- Given a modification type, a range, and the hunk data, returns the end range information
-- for the Gitlab payload
---@param new_line number
---@param old_line number
---@param visual_range LineRange
---@return ReviewerLineInfo
M.get_end_range = function(new_line, old_line, visual_range, current_file)
  -- TODO:
  -- Get the  the visual range to detect the end of the range and new lines.✓
  -- from the current SHA and the old SHA.
  -- Once we have those lines, we pass them into the modification_type function, to get the type.
  -- Pass all three to the result table.
  -- local is_current = reviewer.is_current_sha()
  -- local lines_spanned = visual_range.end_line - visual_range.start_line
  -- local modification_type = M.get_modification_type()
  return {
    old_line = 3,
    new_line = 3,
    type = "old",
  }
end

return M
