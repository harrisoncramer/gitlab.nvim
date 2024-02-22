local u = require("gitlab.utils")
local hunks = require("gitlab.hunks")
local M = {}

---@class Location
---@field location_data LocationData
---@field reviewer_data DiffviewInfo
---@field run function
---@field build_location_data function

---@class ReviewerLineInfo
---@field old_line integer
---@field new_line integer
---@field type string either "new" or "old"

---@class ReviewerRangeInfo
---@field start ReviewerLineInfo
---@field end ReviewerLineInfo

Location = {}
Location.__index = Location
---@param reviewer_data DiffviewInfo
---@param visual_range LineRange | nil
---@return Location
function Location:new(reviewer_data, visual_range)
  local instance = setmetatable({}, Location)
  instance.reviewer_data = reviewer_data
  instance.visual_range = visual_range
  instance.location_data = {
    range_info = {},
  }
  return instance
end

---Executes the location builder and sends the results to the callback function in order to send the comment
---@param cb function
function Location:run(cb)
  self:build_location_data()
  vim.schedule(function()
    cb(self.location_data)
  end)
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
    range_info = nil,
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

  if visual_range == nil then
    self.location_data = location_data
    return
  end

  self:set_start_range(visual_range)
  self:set_end_range(visual_range)
end

-- Helper methods 🤝

-- Returns the matching line from the new SHA.
-- For instance, line 12 in the new SHA may be scroll-linked
-- to line 10 in the old SHA.
---@param line number
---@param offset number
---@return number|nil
function Location:get_line_number_from_new_sha(line, offset)
  local reviewer = require("gitlab.reviewer")
  local is_current_sha = reviewer.is_current_sha()
  if is_current_sha then
    return line
  end
  local matching_line = self:get_matching_line(offset)
  return matching_line
end

-- Returns the matching line from the old SHA.
-- For instance, line 12 in the new SHA may be scroll-linked
-- to line 10 in the old SHA.
---@param line number
---@param offset number
---@return number|nil
function Location:get_line_number_from_old_sha(line, offset)
  local reviewer = require("gitlab.reviewer")
  local is_current_sha = reviewer.is_current_sha()
  if not is_current_sha then
    return line
  end
  local matching_line = self:get_matching_line(offset)
  return matching_line
end

-- Returns the current line number from whatever SHA (new or old)
-- the reviewer is focused in.
---@return number|nil
function Location:get_current_line()
  local reviewer = require("gitlab.reviewer")
  local win_id = reviewer.is_current_sha() and self.reviewer_data.new_sha_win_id or self.reviewer_data.old_sha_win_id
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
  local current_file = require("gitlab.reviewer.diffview").get_current_file()
  if current_file == nil then
    u.notify("Error getting current file from Diffview", vim.log.levels.ERROR)
    return
  end

  local reviewer = require("gitlab.reviewer")
  local win_id = reviewer.is_current_sha() and self.reviewer_data.new_sha_win_id or self.reviewer_data.old_sha_win_id
  if win_id == nil then
    u.notify("Error getting window number of SHA for start range", vim.log.levels.ERROR)
    return
  end

  local current_line = self:get_current_line()
  if current_line == nil then
    u.notify("Error getting window number of SHA for start range", vim.log.levels.ERROR)
    return
  end

  -- If the start line in the range is greater than the current line, pass the
  -- negative difference so we can get the actual start line
  local offset = (current_line - visual_range.start_line) * -1

  local new_line = self:get_line_number_from_new_sha(visual_range.start_line, offset)
  local old_line = self:get_line_number_from_old_sha(visual_range.start_line, offset)
  if new_line == nil or old_line == nil then
    u.notify("Error getting new or old line for start range", vim.log.levels.ERROR)
    return
  end

  local modification_type = hunks.get_modification_type(old_line, new_line, current_file)

  self.location_data.range_info.start = {
    new_line = new_line,
    old_line = old_line,
    type = modification_type == "added" and "new" or "old",
  }
end

---Return the matching line from the other file. For instance, if scrolling in the
---new SHA, find the matching line from the old SHA and return it. The offset
---may be zero.
---@param offset number
---@return number|nil
function Location:get_matching_line(offset)
  return 0
end

-- Given a modification type, a range, and the hunk data, returns the end range information
-- for the Gitlab payload
---@param visual_range LineRange
function Location:set_end_range(visual_range)
  local current_file = require("gitlab.reviewer.diffview").get_current_file()
  if current_file == nil then
    u.notify("Error getting current file from Diffview", vim.log.levels.ERROR)
    return
  end

  local current_line = self:get_current_line()
  if current_line == nil then
    u.notify("Error getting window number of SHA for start range", vim.log.levels.ERROR)
    return
  end

  -- If the end line in the range is greater than the current line, pass the difference
  -- so we can get the actual end line
  local offset = visual_range.end_line - current_line

  local new_line = self:get_line_number_from_new_sha(visual_range.end_line, offset)
  local old_line = self:get_line_number_from_old_sha(visual_range.end_line, offset)

  if new_line == nil or old_line == nil then
    u.notify("Error getting new or old line for end range", vim.log.levels.ERROR)
    return
  end

  local modification_type = hunks.get_modification_type(old_line, new_line, current_file)
  self.location_data.range_info["end"] = {
    new_line = new_line,
    old_line = old_line,
    type = modification_type == "added" and "new" or "old",
  }
end

return M
