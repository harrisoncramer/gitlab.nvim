local u = require("gitlab.utils")
local hunks = require("gitlab.hunks")
local state = require("gitlab.state")

---@class ReviewerLineInfo
---@field old_line? integer
---@field new_line? integer
---@field type "new"|"old"

---@class ReviewerRangeInfo
---@field start ReviewerLineInfo
---@field end ReviewerLineInfo

---@class LocationData
---@field old_line? integer
---@field new_line? integer
---@field line_range? ReviewerRangeInfo

---@class Location
---@field location_data LocationData
---@field reviewer_data DiffviewInfo
---@field run function
---@field build_location_data function
---@field visual_range table

local Location = {}
Location.__index = Location

---Return information about the selection in the reviewer.
---Return nil when the location cannot be created due to missing reviewer data.
---@return Location?
function Location.new()
  local current_win = vim.api.nvim_get_current_win()
  local reviewer_data = require("gitlab.reviewer").get_reviewer_data(current_win)
  if reviewer_data == nil then
    return nil
  end
  local location = {}
  local instance = setmetatable(location, Location)
  instance.reviewer_data = reviewer_data
  instance.base_sha = state.INFO.diff_refs.base_sha
  instance.head_sha = state.INFO.diff_refs.head_sha
  instance:build_location_data()
  return instance
end

---Build the payload for creating a comment based on the file name, modification type of
---the diff, and line numbers.
function Location:build_location_data()
  ---@type DiffviewInfo
  local reviewer_data = self.reviewer_data

  local start_line, end_line = u.get_visual_selection_boundaries()
  ---@type LineRange
  self.visual_range = { start_line = start_line, end_line = end_line }

  ---@type LocationData
  self.location_data = {
    old_line = nil,
    new_line = nil,
    line_range = nil,
  }

  -- Comment on new line: Include only new_line in payload.
  -- Comment on deleted line: Include only old_line in payload.
  -- The line was not found in any hunks, send both lines.
  if reviewer_data.modification_type == "added" then
    self.location_data.old_line = nil
    self.location_data.new_line = reviewer_data.new_line_from_buf
  elseif reviewer_data.modification_type == "deleted" then
    self.location_data.old_line = reviewer_data.old_line_from_buf
    self.location_data.new_line = nil
  elseif
    reviewer_data.modification_type == "unmodified" or reviewer_data.modification_type == "bad_file_unmodified"
  then
    self.location_data.old_line = reviewer_data.old_line_from_buf
    self.location_data.new_line = reviewer_data.new_line_from_buf
  end

  -- TODO: Don't skip line_range for single-line comments (Gitlab doesn't skip them either).
  if end_line > start_line then
    self.location_data.line_range = {
      start = {},
      ["end"] = {},
    }
  else
    return
  end

  self:set_range_start()
  self:set_range_end()

  -- Ranged comments should always use the end of the range.
  -- Otherwise they will not highlight the full comment in Gitlab.
  self.location_data.old_line = self.location_data.line_range["end"].old_line
  self.location_data.new_line = self.location_data.line_range["end"].new_line
end

-- Helper methods 🤝

---Return the matching line number from the new version of the file.
---For instance, line 12 in the new version may be scroll-linked to line 10 in the old
---version.
---@param linenr integer The starting or ending line of the current selection
---@return integer?
function Location:get_line_number_from_new_sha(linenr)
  if self.reviewer_data.new_sha_focused then
    return linenr
  end
  -- Otherwise we want to get the matching line in the opposite buffer
  return hunks.calculate_matching_line_new(
    self.base_sha,
    self.head_sha,
    self.reviewer_data.file_name,
    self.reviewer_data.old_file_name,
    linenr
  )
end

---Return the matching line number from the old version of the file.
---For instance, line 12 in the new version may be scroll-linked to line 10 in the old
---version.
---@param linenr integer The starting or ending line of the current selection
---@return integer?
function Location:get_line_number_from_old_sha(linenr)
  if not self.reviewer_data.new_sha_focused then
    return linenr
  end

  -- Otherwise we want to get the matching line in the opposite buffer
  return hunks.calculate_matching_line_new(
    self.head_sha,
    self.base_sha,
    self.reviewer_data.file_name,
    self.reviewer_data.old_file_name,
    linenr
  )
end

---Return the current line number from whatever version (new or old) the reviewer is
---focused in.
---@return integer?
function Location:get_current_line()
  if self.reviewer_data.current_win_id == nil then
    return
  end

  local current_line = vim.api.nvim_win_get_cursor(self.reviewer_data.current_win_id)[1]
  return current_line
end

---Set the range start to the location_data for the Gitlab payload based on the
---modification type, visual selection range, and the hunk data.
function Location:set_range_start()
  local current_file = require("gitlab.reviewer").get_current_file_path()
  if current_file == nil then
    u.notify("Error getting current file from Diffview", vim.log.levels.ERROR)
    return
  end

  if self.reviewer_data.current_win_id == nil then
    u.notify("Error getting window number of SHA for start of range", vim.log.levels.ERROR)
    return
  end

  local current_line = self:get_current_line()
  if current_line == nil then
    u.notify("Error getting current line for start of range", vim.log.levels.ERROR)
    return
  end

  local new_line = self:get_line_number_from_new_sha(self.visual_range.start_line)
  local old_line = self:get_line_number_from_old_sha(self.visual_range.start_line)
  if
    (new_line == nil and self.reviewer_data.modification_type ~= "deleted")
    or (old_line == nil and self.reviewer_data.modification_type ~= "added")
  then
    u.notify("Error getting new or old line for start of range", vim.log.levels.ERROR)
    return
  end

  local modification_type = hunks.get_modification_type(old_line, new_line, self.reviewer_data.new_sha_focused)
  if modification_type == nil then
    u.notify("Error getting modification type for start of range", vim.log.levels.ERROR)
    return
  end

  self.location_data.line_range.start = {
    new_line = modification_type ~= "deleted" and new_line or nil,
    old_line = modification_type ~= "added" and old_line or nil,
    -- FIXME: The type should only be "old" explicitly for comments on deleted lines.
    -- For unchanged lines this should be empty. Apart from that, the modification type
    -- can also be "expanded" (when commenting on lines that are more than 3 lines away
    -- from any change, thus are on folded lines that the user expanded manually.
    type = modification_type == "added" and "new" or "old",
  }
end

---Set the range end to the location_data for the Gitlab payload based on the
---modification type, visual selection range, and the hunk data.
function Location:set_range_end()
  local current_file = require("gitlab.reviewer").get_current_file_path()
  if current_file == nil then
    u.notify("Error getting current file from Diffview", vim.log.levels.ERROR)
    return
  end

  if self.reviewer_data.current_win_id == nil then
    u.notify("Error getting window number of SHA for end of range", vim.log.levels.ERROR)
    return
  end

  local current_line = self:get_current_line()
  if current_line == nil then
    u.notify("Error getting current line for end of range", vim.log.levels.ERROR)
    return
  end

  local new_line = self:get_line_number_from_new_sha(self.visual_range.end_line)
  local old_line = self:get_line_number_from_old_sha(self.visual_range.end_line)

  if
    (new_line == nil and self.reviewer_data.modification_type ~= "deleted")
    or (old_line == nil and self.reviewer_data.modification_type ~= "added")
  then
    u.notify("Error getting new or old line for end of range", vim.log.levels.ERROR)
    return
  end

  local modification_type = hunks.get_modification_type(old_line, new_line, self.reviewer_data.new_sha_focused)
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
