-- This module is responsible for creating new comments
-- in the reviewer's buffer. The reviewer will pass back
-- to this module the data required to make the API calls
local Popup = require("nui.popup")
local Layout = require("nui.layout")
local state = require("gitlab.state")
local job = require("gitlab.job")
local u = require("gitlab.utils")
local git = require("gitlab.git")
local discussions = require("gitlab.actions.discussions")
local draft_notes = require("gitlab.actions.draft_notes")
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
  local draft_popup = Popup(u.create_box_popup_state("Draft", false))

  M.comment_popup = comment_popup
  M.draft_popup = draft_popup

  local internal_layout = Layout.Box({
    Layout.Box(comment_popup, { grow = 1 }),
    Layout.Box(draft_popup, { size = 3 }),
  }, { dir = "col" })

  local layout = Layout({
    position = "50%",
    relative = "editor",
    size = {
      width = "50%",
      height = "55%",
    },
  }, internal_layout)

  local popup_opts = {
    action_before_close = true,
    action_before_exit = false,
  }

  state.set_popup_keymaps(M.draft_popup, function() M.get_text_and_create_comment(false) end, miscellaneous.attach_file,
    popup_opts)
  state.set_popup_keymaps(M.comment_popup, function() M.get_text_and_create_comment(false) end, miscellaneous
    .attach_file, popup_opts)

  layout:mount()

  vim.schedule(function()
    local default_to_draft = state.settings.comments.default_to_draft
    vim.api.nvim_buf_set_lines(M.draft_popup.bufnr, 0, -1, false, { u.bool_to_string(default_to_draft) })
  end)
end

---Gets text from the popup and creates a note or comment
---@param unlinked boolean
M.get_text_and_create_comment = function(unlinked)
  local text = u.get_buffer_text(M.comment_popup.bufnr)
  M.confirm_create_comment(text, nil, unlinked)
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
  end, miscellaneous.attach_file, miscellaneous.editable_popup_opts)
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
  local selected_lines = u.get_lines(start_line, end_line)

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
      M.confirm_create_comment(text, { start_line = start_line, end_line = end_line }, false)
    else
      M.confirm_create_comment(text, nil, false)
    end
  end, miscellaneous.attach_file, miscellaneous.editable_popup_opts)
end

M.create_note = function()
  local note_popup = create_comment_popup()
  local draft_popup = Popup(u.create_box_popup_state("Draft", false))

  M.comment_popup = note_popup
  M.draft_popup = draft_popup

  local internal_layout = Layout.Box({
    Layout.Box(note_popup, { grow = 1 }),
    Layout.Box(draft_popup, { size = 3 }),
  }, { dir = "col" })

  local layout = Layout({
    position = "50%",
    relative = "editor",
    size = {
      width = "50%",
      height = "55%",
    },
  }, internal_layout)

  local popup_opts = {
    action_before_close = true,
    action_before_exit = false,
  }

  state.set_popup_keymaps(M.draft_popup, function() M.get_text_and_create_comment(true) end, miscellaneous.attach_file,
    popup_opts)
  state.set_popup_keymaps(M.comment_popup, function() M.get_text_and_create_comment(true) end, miscellaneous.attach_file,
    popup_opts)

  layout:mount()

  vim.schedule(function()
    local default_to_draft = state.settings.comments.default_to_draft
    vim.api.nvim_buf_set_lines(M.draft_popup.bufnr, 0, -1, false, { u.bool_to_string(default_to_draft) })
  end)
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

  local is_draft = M.draft_popup and u.string_to_bool(u.get_buffer_text(M.draft_popup.bufnr))
  if unlinked then
    local body = { comment = text }
    local endpoint = is_draft and "/mr/draft_notes/" or "/mr/comment"
    job.run_job(endpoint, "POST", body, function(data)
      u.notify(is_draft and "Draft note created!" or "Note created!", vim.log.levels.INFO)
      if is_draft then
        draft_notes.add_draft_note({ draft_note = data.draft_note, has_position = false })
      else
        discussions.add_discussion({ data = data, has_position = false })
      end

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

  local endpoint = is_draft and "/mr/draft_notes/" or "/mr/comment"
  job.run_job(endpoint, "POST", body, function(data)
    u.notify(is_draft and "Draft comment created!" or "Comment created!", vim.log.levels.INFO)
    if is_draft then
      draft_notes.add_draft_note({ draft_note = data.draft_note, has_position = true })
    else
      discussions.add_discussion({ data = data, has_position = true })
    end
    discussions.refresh()
  end)
end

return M
