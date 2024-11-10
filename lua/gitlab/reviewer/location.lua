local u = require("gitlab.utils")
local hunks = require("gitlab.hunks")
local state = require("gitlab.state")

---@class Location
---@field location_data LocationData
---@field reviewer_data DiffviewInfo
---@field run function
---@field build_location_data function

---@class ReviewerLineInfo
---@field old_line integer|nil
---@field new_line integer|nil
---@field type "new"|"old"

---@class ReviewerRangeInfo
---@field start ReviewerLineInfo
---@field end ReviewerLineInfo

local Location = {}
Location.__index = Location
---@param reviewer_data DiffviewInfo
---@param visual_range LineRange | nil
---@return Location
function Location.new(reviewer_data, visual_range)
  local location = {}
  local instance = setmetatable(location, Location)
  instance.reviewer_data = reviewer_data
  instance.visual_range = visual_range
  instance.base_sha = state.INFO.diff_refs.base_sha
  instance.head_sha = state.INFO.diff_refs.head_sha
  return instance
end

---Takes in information about the current changes, such as the file name, modification type of the diff, and the line numbers
---and builds the appropriate payload when creating a comment.
function Location:build_location_data()
  ---@type DiffviewInfo
  local reviewer_data = self.reviewer_data
  ---@type LineRange | nil
  local visual_range = self.visual_range

  ---@type LocationData
  local location_data = {
    old_line = nil,
    new_line = nil,
    line_range = nil,
  }

  -- Comment on new line: Include only new_line in payload.
  -- Comment on deleted line: Include only old_line in payload.
  -- The line was not found in any hunks, send both lines.
  if reviewer_data.modification_type == "added" then
    location_data.old_line = nil
    location_data.new_line = reviewer_data.new_line_from_buf
  elseif reviewer_data.modification_type == "deleted" then
    location_data.old_line = reviewer_data.old_line_from_buf
    location_data.new_line = nil
  elseif
    reviewer_data.modification_type == "unmodified" or reviewer_data.modification_type == "bad_file_unmodified"
  then
    location_data.old_line = reviewer_data.old_line_from_buf
    location_data.new_line = reviewer_data.new_line_from_buf
  end

  self.location_data = location_data
  if visual_range == nil then
    return
  else
    self.location_data.line_range = {
      start = {},
      ["end"] = {},
    }
  end

  self:set_start_range(visual_range)
  self:set_end_range(visual_range)

  -- Ranged comments should always use the end of the range.
  -- Otherwise they will not highlight the full comment in Gitlab.
  self.location_data.old_line = self.location_data.line_range["end"].old_line
  self.location_data.new_line = self.location_data.line_range["end"].new_line
end

-- Helper methods 🤝

-- Returns the matching line from the new SHA.
-- For instance, line 12 in the new SHA may be scroll-linked
-- to line 10 in the old SHA.
---@param line number
---@return number|nil
function Location:get_line_number_from_new_sha(line)
  local reviewer = require("gitlab.reviewer")
  local is_current_sha_focused = reviewer.is_current_sha_focused()
  if is_current_sha_focused then
    return line
  end
  -- Otherwise we want to get the matching line in the opposite buffer
  return hunks.calculate_matching_line_new(
    self.base_sha,
    self.head_sha,
    self.reviewer_data.file_name,
    self.reviewer_data.old_file_name,
    line
  )
end

-- Returns the matching line from the old SHA.
-- For instance, line 12 in the new SHA may be scroll-linked
-- to line 10 in the old SHA.
---@param line number
---@return number|nil
function Location:get_line_number_from_old_sha(line)
  local reviewer = require("gitlab.reviewer")
  local is_current_sha_focused = reviewer.is_current_sha_focused()
  if not is_current_sha_focused then
    return line
  end

  -- Otherwise we want to get the matching line in the opposite buffer
  return hunks.calculate_matching_line_new(
    self.head_sha,
    self.base_sha,
    self.reviewer_data.file_name,
    self.reviewer_data.old_file_name,
    line
  )
end

-- Returns the current line number from whatever SHA (new or old)
-- the reviewer is focused in.
---@return number|nil
function Location:get_current_line()
  local reviewer = require("gitlab.reviewer")
  local win_id = reviewer.is_current_sha_focused() and self.reviewer_data.new_sha_win_id
    or self.reviewer_data.old_sha_win_id
  if win_id == nil then
    return
  end

  local current_line = vim.api.nvim_win_get_cursor(win_id)[1]
  return current_line
end

-- Given a new_line and old_line from the start of a ranged comment, returns the start
-- range information for the Gitlab payload
---@param visual_range LineRange
---@return ReviewerLineInfo|nil
function Location:set_start_range(visual_range)
  local current_file = require("gitlab.reviewer").get_current_file_path()
  if current_file == nil then
    u.notify("Error getting current file from Diffview", vim.log.levels.ERROR)
    return
  end

  local reviewer = require("gitlab.reviewer")
  local is_current_sha_focused = reviewer.is_current_sha_focused()
  local win_id = is_current_sha_focused and self.reviewer_data.new_sha_win_id or self.reviewer_data.old_sha_win_id
  if win_id == nil then
    u.notify("Error getting window number of SHA for start range", vim.log.levels.ERROR)
    return
  end

  local current_line = self:get_current_line()
  if current_line == nil then
    u.notify("Error getting current line for start range", vim.log.levels.ERROR)
    return
  end

  local new_line = self:get_line_number_from_new_sha(visual_range.start_line)
  local old_line = self:get_line_number_from_old_sha(visual_range.start_line)
  if
    (new_line == nil and self.reviewer_data.modification_type ~= "deleted")
    or (old_line == nil and self.reviewer_data.modification_type ~= "added")
  then
    u.notify("Error getting new or old line for start range", vim.log.levels.ERROR)
    return
  end

  local modification_type = hunks.get_modification_type(old_line, new_line, is_current_sha_focused)
  if modification_type == nil then
    u.notify("Error getting modification type for start of range", vim.log.levels.ERROR)
    return
  end

  self.location_data.line_range.start = {
    new_line = modification_type ~= "deleted" and new_line or nil,
    old_line = modification_type ~= "added" and old_line or nil,
    type = modification_type == "added" and "new" or "old",
  }
end

-- Given a modification type, a range, and the hunk data, returns the end range information
-- for the Gitlab payload
---@param visual_range LineRange
function Location:set_end_range(visual_range)
  local current_file = require("gitlab.reviewer").get_current_file_path()
  if current_file == nil then
    u.notify("Error getting current file from Diffview", vim.log.levels.ERROR)
    return
  end

  local current_line = self:get_current_line()
  if current_line == nil then
    u.notify("Error getting current line for end range", vim.log.levels.ERROR)
    return
  end

  local new_line = self:get_line_number_from_new_sha(visual_range.end_line)
  local old_line = self:get_line_number_from_old_sha(visual_range.end_line)

  if
    (new_line == nil and self.reviewer_data.modification_type ~= "deleted")
    or (old_line == nil and self.reviewer_data.modification_type ~= "added")
  then
    u.notify("Error getting new or old line for end range", vim.log.levels.ERROR)
    return
  end

  local reviewer = require("gitlab.reviewer")
  local is_current_sha_focused = reviewer.is_current_sha_focused()
  local modification_type = hunks.get_modification_type(old_line, new_line, is_current_sha_focused)
  if modification_type == nil then
    u.notify("Error getting modification type for end of range", vim.log.levels.ERROR)
    return
  end

  self.location_data.line_range["end"] = {
    new_line = modification_type ~= "deleted" and new_line or nil,
    old_line = modification_type ~= "added" and old_line or nil,
    type = modification_type == "added" and "new" or "old",
  }
end

return Location
