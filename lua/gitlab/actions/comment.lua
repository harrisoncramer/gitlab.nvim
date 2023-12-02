-- This module is responsible for creating new comments
-- in the reviewer's buffer. The reviewer will pass back
-- to this module the data required to make the API calls
local Popup = require("nui.popup")
local state = require("gitlab.state")
local job = require("gitlab.job")
local u = require("gitlab.utils")
local discussions = require("gitlab.actions.discussions")
local miscellaneous = require("gitlab.actions.miscellaneous")
local reviewer = require("gitlab.reviewer")
local M = {}

-- Popup creation is wrapped in a function so that it is performed *after* user
-- configuration has been merged with default configuration, not when this file is being
-- required.
local function create_comment_popup()
  return Popup(
    u.create_popup_state(
      "Comment",
      state.settings.popup.comment.border or state.settings.popup.border,
      state.settings.popup.comment.width or state.settings.popup.width,
      state.settings.popup.comment.height or state.settings.popup.height,
      state.settings.popup.comment.opacity or state.settings.popup.opacity
    )
  )
end

-- This function will open a comment popup in order to create a comment on the changed/updated
-- line in the current MR
M.create_comment = function()
  local comment_popup = create_comment_popup()
  comment_popup:mount()
  state.set_popup_keymaps(comment_popup, function(text)
    M.confirm_create_comment(text)
  end, miscellaneous.attach_file)
end

---Create multiline comment for the last selection.
M.create_multiline_comment = function()
  if not u.check_visual_mode() then
    return
  end
  local comment_popup = create_comment_popup()
  local start_line, end_line = u.get_visual_selection_boundaries()
  comment_popup:mount()
  state.set_popup_keymaps(comment_popup, function(text)
    M.confirm_create_comment(text, { start_line = start_line, end_line = end_line })
  end, miscellaneous.attach_file)
end

---Create comment prepopulated with gitlab suggestion
---https://docs.gitlab.com/ee/user/project/merge_requests/reviews/suggestions.html
M.create_comment_suggestion = function()
  if not u.check_visual_mode() then
    return
  end
  local comment_popup = create_comment_popup()
  local start_line, end_line = u.get_visual_selection_boundaries()
  local current_line = vim.api.nvim_win_get_cursor(0)[1]
  local range = end_line - start_line
  local backticks = "```"
  local selected_lines = reviewer.get_lines(start_line, end_line)

  for line in ipairs(selected_lines) do
    if string.match(line, "^```$") then
      backticks = "````"
      break
    end
  end

  local suggestion_start
  if start_line == current_line then
    suggestion_start = backticks .. "suggestion:-0+" .. range
  elseif end_line == current_line then
    suggestion_start = backticks .. "suggestion:-" .. range .. "+0"
  else
    -- This should never happen afaik
    u.notify("Unexpected suggestion position", vim.log.levels.ERROR)
    return
  end
  suggestion_start = suggestion_start
  local suggestion_lines = {}
  table.insert(suggestion_lines, suggestion_start)
  vim.list_extend(suggestion_lines, selected_lines)
  table.insert(suggestion_lines, backticks)

  comment_popup:mount()
  vim.api.nvim_buf_set_lines(comment_popup.bufnr, 0, 0, false, suggestion_lines)
  state.set_popup_keymaps(comment_popup, function(text)
    if range > 0 then
      M.confirm_create_comment(text, { start_line = start_line, end_line = end_line })
    else
      M.confirm_create_comment(text, nil)
    end
  end, miscellaneous.attach_file)
end

M.create_note = function()
  local note_popup = Popup(
    u.create_popup_state(
      "Note",
      state.settings.popup.note.border or state.settings.popup.border,
      state.settings.popup.note.width or state.settings.popup.width,
      state.settings.popup.note.height or state.settings.popup.height,
      state.settings.popup.note.opacity or state.settings.popup.opacity
    )
  )
  note_popup:mount()
  state.set_popup_keymaps(note_popup, function(text)
    M.confirm_create_comment(text, nil, true)
  end, miscellaneous.attach_file)
end

---@class LineRange
---@field start_line integer
---@field end_line integer

---@class ReviewerLineInfo
---@field old_line integer
---@field new_line integer
---@field type string either "new" or "old"

---@class ReviewerRangeInfo
---@field start ReviewerLineInfo
---@field end ReviewerLineInfo

---@class ReviewerInfo
---@field file_name string
---@field old_line integer | nil
---@field new_line integer | nil
---@field range_info ReviewerRangeInfo

---This function (settings.popup.perform_action) will send the comment to the Go server
---@param text string comment text
---@param range LineRange | nil range of visuel selection or nil
---@param unlinked boolean | nil if true, the comment is not linked to a line
M.confirm_create_comment = function(text, range, unlinked)
  if text == nil then
    u.notify("Reviewer did not provide text of change", vim.log.levels.ERROR)
    return
  end

  if unlinked then
    local body = { comment = text }
    job.run_job("/comment", "POST", body, function(data)
      u.notify("Note created!", vim.log.levels.INFO)
      discussions.add_discussion({ data = data, unlinked = true })
    end)
    return
  end

  local reviewer_info = reviewer.get_location(range)
  if not reviewer_info then
    return
  end

  local revision = state.MR_REVISIONS[1]
  local body = {
    comment = text,
    file_name = reviewer_info.file_name,
    old_line = reviewer_info.old_line,
    new_line = reviewer_info.new_line,
    base_commit_sha = revision.base_commit_sha,
    start_commit_sha = revision.start_commit_sha,
    head_commit_sha = revision.head_commit_sha,
    type = "text",
    line_range = reviewer_info.range_info,
  }

  job.run_job("/comment", "POST", body, function(data)
    u.notify("Comment created!", vim.log.levels.INFO)
    discussions.add_discussion({ data = data, unlinked = false })
    discussions.refresh_discussion_data()
  end)
end

return M
