local u = require("gitlab.utils")
local hunks = require("gitlab.hunks")
local M = {}

---@class Location
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
  return instance
end

---Executes the location builder and sends the results to the callback function in order to send the comment
---@param cb function
function Location:run(cb)
  local location_data = self:build_location_data()
  vim.schedule(function()
    cb(location_data)
  end)
end

---Takes in information about the current changes, such as the file name, modification type of the diff, and the line numbers
---and builds the appropriate payload when creating a comment.
---@return CommentPayload
function Location:build_location_data()
  ---@type DiffviewInfo
  local reviewer_data = self.reviewer_data
  ---@type LineRange | nil
  local visual_range = self.visual_range

  vim.print(reviewer_data)
  vim.print(visual_range)
  -- ---@type CommentPayload
  -- local payload = {
  --   file_name = file_name,
  --   new_line = nil,
  --   old_line = nil,
  --   range_info = nil,
  -- }
  --
  -- -- Comment on new line: Include only new_line in payload.
  -- if modification_type == "added" then
  --   payload.old_line = nil
  --   payload.new_line = new_line
  --   -- Comment on deleted line: Include only old_line in payload.
  -- elseif modification_type == "deleted" then
  --   payload.old_line = old_line
  --   payload.new_line = nil
  --   -- The line was not found in any hunks, send both lines.
  -- elseif modification_type == "unmodified" or modification_type == "bad_file_unmodified" then
  --   payload.old_line = old_line
  --   payload.new_line = new_line
  -- end
  --
  -- if visual_range == nil then
  --   return payload
  -- end
  --
  -- local start_range_info = self:get_start_range(visual_range)
  -- local end_range_info = self:get_end_range(visual_range)
  --
  -- -- Failed to get range
  -- if start_range_info == nil or end_range_info == nil then
  --   return nil
  -- end
  --
  -- payload.range_info = {
  --   start = {
  --     old_line = start_range_info.old_line,
  --     new_line = start_range_info.new_line,
  --     type = start_range_info.type,
  --   },
  --   ["end"] = {
  --     old_line = end_range_info.old_line,
  --     new_line = end_range_info.new_line,
  --     type = end_range_info.type,
  --   },
  -- }
  --
  -- return payload
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
  local win_id = reviewer.is_current_sha() and reviewer.get_winnr_of_new_sha() or reviewer.get_winnr_of_old_sha()
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
function Location:get_start_range(visual_range)
  local current_file = require("gitlab.reviewer.diffview").get_current_file()
  if current_file == nil then
    u.notify("Error getting current file from Diffview", vim.log.levels.ERROR)
    return
  end

  local reviewer = require("gitlab.reviewer")
  local win_id = reviewer.is_current_sha() and reviewer.get_winnr_of_new_sha() or reviewer.get_winnr_of_old_sha()
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

  return {
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
  -- local view = diffview_lib.get_current_view()
  -- local layout = view.cur_layout
  -- if layout == nil then
  --   return nil
  -- end
  -- local current_bufnr = M.is_current_sha() and layout.b.file.bufnr or layout.a.file.bufnr
  -- local opposite_bufnr = M.is_current_sha() and layout.a.file.bufnr or layout.b.file.bufnr
  --
  -- local current_win_id = u.get_window_id_by_buffer_id(current_bufnr)
  -- if current_win_id == nil then
  --   return nil
  -- end
  --
  -- -- Adjust the current cursor X number of lines
  -- local original_cursor_position = vim.api.nvim_win_get_cursor(current_win_id)
  -- local new_cursor_pos = { original_cursor_position[1] + offset, original_cursor_position[2] }
  --
  -- vim.api.nvim_win_set_cursor(current_win_id, new_cursor_pos) -- Adjust cursor position by offset
  -- vim.cmd("redraw")
  --
  -- local oppposite_win_id = u.get_window_id_by_buffer_id(opposite_bufnr)
  -- if oppposite_win_id == nil then
  --   return nil
  -- end
  --
  -- local result = vim.api.nvim_win_get_cursor(oppposite_win_id)[1]
  --
  -- vim.api.nvim_win_set_cursor(current_win_id, original_cursor_position) -- Reset cursor position
  -- vim.cmd("redraw")
  -- return result
end

-- Given a modification type, a range, and the hunk data, returns the end range information
-- for the Gitlab payload
---@param visual_range LineRange
---@return ReviewerLineInfo|nil
function Location:get_end_range(visual_range)
  local current_file = require("gitlab.reviewer.diffview").get_current_file()
  if current_file == nil then
    u.notify("Error getting current file from Diffview", vim.log.levels.ERROR)
    return
  end

  local current_line = Location:get_current_line()
  if current_line == nil then
    u.notify("Error getting window number of SHA for start range", vim.log.levels.ERROR)
    return
  end

  -- If the end line in the range is greater than the current line, pass the difference
  -- so we can get the actual end line
  local offset = visual_range.end_line - current_line

  local new_line = Location:get_line_number_from_new_sha(visual_range.end_line, offset)
  local old_line = Location:get_line_number_from_old_sha(visual_range.end_line, offset)

  if new_line == nil or old_line == nil then
    u.notify("Error getting new or old line for end range", vim.log.levels.ERROR)
    return
  end

  local modification_type = hunks.get_modification_type(old_line, new_line, current_file)
  return {
    new_line = new_line,
    old_line = old_line,
    type = modification_type == "added" and "new" or "old",
  }
end

return M
