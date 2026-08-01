local hunks = require("gitlab.hunks")

---@class LocationData
---@field old_line? integer
---@field new_line? integer
---@field line_range? LineRange

---@class Location
---@field location_data LocationData
---@field reviewer_data ReviewerData
---@field new fun(reviewer_data: ReviewerData, diff_hunks: Hunk[]): Location
---@field build_location_data fun()

local Location = {}
Location.__index = Location

---Build a Location from already-resolved reviewer data and diff hunks.
---@param reviewer_data ReviewerData
---@param diff_hunks Hunk[]
---@return Location
function Location.new(reviewer_data, diff_hunks)
  local instance = setmetatable({}, Location)
  instance.reviewer_data = reviewer_data
  instance:build_location_data(diff_hunks)
  return instance
end

---Build the payload for creating a comment.
---@param diff_hunks Hunk[]
function Location:build_location_data(diff_hunks)
  local line_range = {
    start = hunks.get_line_position(diff_hunks, self.reviewer_data.start_line, self.reviewer_data.new_file_focused),
    ["end"] = hunks.get_line_position(diff_hunks, self.reviewer_data.end_line, self.reviewer_data.new_file_focused),
  }
  ---@type LocationData
  self.location_data = {
    -- Top-level old_line and new_line must correspond to the end of the range to be
    -- placed correctly in Gitlab. They are only set if they match the modification
    -- type.
    old_line = line_range["end"].type ~= "new" and line_range["end"].old_line or nil,
    new_line = line_range["end"].type ~= "old" and line_range["end"].new_line or nil,
    line_range = line_range,
  }
  -- TODO: Warn the user when position.type == "" (unmodified) while their selection was
  -- made on the "wrong" side, since gitlab.nvim may render such a comment's diagnostic
  -- on the other side of the diff than the one the user was looking at. This used to
  -- exist (see the removed "bad_file_unmodified" modification type) but was lost in a
  -- refactor; reviving it needs its own design, since which side gitlab.nvim actually
  -- picks incorrectly doesn't reflect the start of the comment range and can show a
  -- comment spanning "new-unchanged" lines on the old file even if it belongs to the
  -- new file.
end

return Location
