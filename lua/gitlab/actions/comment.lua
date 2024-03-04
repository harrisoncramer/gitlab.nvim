-- This module is responsible for creating new comments
-- in the reviewer's buffer. The reviewer will pass back
-- to this module the data required to make the API calls
local Popup = require("nui.popup")
local state = require("gitlab.state")
local job = require("gitlab.job")
local u = require("gitlab.utils")
local git = require("gitlab.git")
local discussions = require("gitlab.actions.discussions")
local miscellaneous = require("gitlab.actions.miscellaneous")
local reviewer = require("gitlab.reviewer")
local Location = require("gitlab.reviewer.location")
local M = {}

-- Popup creation is wrapped in a function so that it is performed *after* user
-- configuration has been merged with default configuration, not when this file is being
-- required.
local function create_comment_popup()
  return Popup(u.create_popup_state("Comment", state.settings.popup.comment))
end

-- This function will open a comment popup in order to create a comment on the changed/updated
-- line in the current MR
M.create_comment = function()
  local has_clean_tree = git.has_clean_tree()
  local is_modified = vim.api.nvim_buf_get_option(0, "modified")
  if state.settings.reviewer_settings.diffview.imply_local and (is_modified or not has_clean_tree) then
    u.notify(
      "Cannot leave comments on changed files. \n Please stash all local changes or push them to the feature branch.",
      vim.log.levels.WARN
    )
    return
  end
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
  vim.api.nvim_buf_set_lines(comment_popup.bufnr, 0, -1, false, suggestion_lines)
  state.set_popup_keymaps(comment_popup, function(text)
    if range > 0 then
      M.confirm_create_comment(text, { start_line = start_line, end_line = end_line })
    else
      M.confirm_create_comment(text, nil)
    end
  end, miscellaneous.attach_file)
end

M.create_note = function()
  local note_popup = Popup(u.create_popup_state("Note", state.settings.popup.note))
  note_popup:mount()
  state.set_popup_keymaps(note_popup, function(text)
    M.confirm_create_comment(text, nil, true)
  end, miscellaneous.attach_file)
end

---This function (settings.popup.perform_action) will send the comment to the Go server
---@param text string comment text
---@param visual_range LineRange | nil range of visual selection or nil
---@param unlinked boolean | nil if true, the comment is not linked to a line
M.confirm_create_comment = function(text, visual_range, unlinked)
  if text == nil then
    u.notify("Reviewer did not provide text of change", vim.log.levels.ERROR)
    return
  end

  if unlinked then
    local body = { comment = text }
    job.run_job("/mr/comment", "POST", body, function(data)
      u.notify("Note created!", vim.log.levels.INFO)
      discussions.add_discussion({ data = data, unlinked = true })
      discussions.refresh()
    end)
    return
  end

  local reviewer_data = reviewer.get_reviewer_data()
  if reviewer_data == nil then
    u.notify("Error getting reviewer data", vim.log.levels.ERROR)
    return
  end

  local location = Location.new(reviewer_data, visual_range)
  location:build_location_data()
  local location_data = location.location_data
  if location_data == nil then
    u.notify("Error getting location information", vim.log.levels.ERROR)
    return
  end

  local revision = state.MR_REVISIONS[1]
  local body = {
    type = "text",
    comment = text,
    file_name = reviewer_data.file_name,
    base_commit_sha = revision.base_commit_sha,
    start_commit_sha = revision.start_commit_sha,
    head_commit_sha = revision.head_commit_sha,
    old_line = location_data.old_line,
    new_line = location_data.new_line,
    line_range = location_data.line_range,
  }

  job.run_job("/mr/comment", "POST", body, function(data)
    u.notify("Comment created!", vim.log.levels.INFO)
    discussions.add_discussion({ data = data, unlinked = false })
    discussions.refresh()
  end)
end

return M
