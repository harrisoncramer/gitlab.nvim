--- This module is responsible for creating new comments
--- in the reviewer's buffer. The reviewer will pass back
--- to this module the data required to make the API calls
local Popup = require("nui.popup")
local Layout = require("nui.layout")
local state = require("gitlab.state")
local job = require("gitlab.job")
local u = require("gitlab.utils")
local popup = require("gitlab.popup")
local git = require("gitlab.git")
local discussions = require("gitlab.actions.discussions")
local draft_notes = require("gitlab.actions.draft_notes")
local miscellaneous = require("gitlab.actions.miscellaneous")
local reviewer = require("gitlab.reviewer")
local Location = require("gitlab.reviewer.location")

local M = {
  current_win = nil,
  start_line = nil,
  end_line = nil,
  draft_popup = nil,
  comment_popup = nil,
}

---Fires the API that sends the comment data to the Go server, called when you "confirm" creation
---via the M.settings.keymaps.popup.perform_action keybinding
---@param text string comment text
---@param visual_range LineRange | nil range of visual selection or nil
---@param unlinked boolean if true, the comment is not linked to a line
---@param discussion_id string | nil The ID of the discussion to which the reply is responding, nil if not a reply
local confirm_create_comment = function(text, visual_range, unlinked, discussion_id)
  if text == nil then
    u.notify("Reviewer did not provide text of change", vim.log.levels.ERROR)
    return
  end

  local is_draft = M.draft_popup and u.string_to_bool(u.get_buffer_text(M.draft_popup.bufnr))

  -- Creating a normal reply to a discussion
  if discussion_id ~= nil and not is_draft then
    local body = { discussion_id = discussion_id, reply = text, draft = is_draft }
    job.run_job("/mr/reply", "POST", body, function()
      u.notify("Sent reply!", vim.log.levels.INFO)
      discussions.rebuild_view(unlinked)
    end)
    return
  end

  -- Creating a draft reply, in response to a discussion ID
  if discussion_id ~= nil and is_draft then
    local body = { comment = text, discussion_id = discussion_id }
    job.run_job("/mr/draft_notes/", "POST", body, function()
      u.notify("Draft reply created!", vim.log.levels.INFO)
      draft_notes.load_draft_notes(function()
        discussions.rebuild_view(unlinked)
      end)
    end)
    return
  end

  -- Creating a note (unlinked comment)
  if unlinked and discussion_id == nil then
    local body = { comment = text }
    local endpoint = is_draft and "/mr/draft_notes/" or "/mr/comment"
    job.run_job(endpoint, "POST", body, function()
      u.notify(is_draft and "Draft note created!" or "Note created!", vim.log.levels.INFO)
      if is_draft then
        draft_notes.load_draft_notes(function()
          discussions.rebuild_view(unlinked)
        end)
      else
        discussions.rebuild_view(unlinked)
      end
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
  local position_data = {
    file_name = reviewer_data.file_name,
    old_file_name = reviewer_data.old_file_name,
    base_commit_sha = revision.base_commit_sha,
    start_commit_sha = revision.start_commit_sha,
    head_commit_sha = revision.head_commit_sha,
    old_line = location_data.old_line,
    new_line = location_data.new_line,
    line_range = location_data.line_range,
  }

  -- Creating a new comment (linked to specific changes)
  local body = u.merge({ type = "text", comment = text }, position_data)
  local endpoint = is_draft and "/mr/draft_notes/" or "/mr/comment"
  job.run_job(endpoint, "POST", body, function()
    u.notify(is_draft and "Draft comment created!" or "Comment created!", vim.log.levels.INFO)
    if is_draft then
      draft_notes.load_draft_notes(function()
        discussions.rebuild_view(unlinked)
      end)
    else
      discussions.rebuild_view(unlinked)
    end
  end)
end

-- This function will actually send the deletion to Gitlab when you make a selection,
-- and re-render the tree
---@param note_id integer
---@param discussion_id string
---@param unlinked boolean
M.confirm_delete_comment = function(note_id, discussion_id, unlinked)
  local body = { discussion_id = discussion_id, note_id = tonumber(note_id) }
  job.run_job("/mr/comment", "DELETE", body, function(data)
    u.notify(data.message, vim.log.levels.INFO)
    discussions.rebuild_view(unlinked)
  end)
end

---This function sends the edited comment to the Go server
---@param discussion_id string
---@param note_id integer
---@param unlinked boolean
M.confirm_edit_comment = function(discussion_id, note_id, unlinked)
  return function(text)
    local body = {
      discussion_id = discussion_id,
      note_id = note_id,
      comment = text,
    }
    job.run_job("/mr/comment", "PATCH", body, function(data)
      u.notify(data.message, vim.log.levels.INFO)
      discussions.rebuild_view(unlinked)
    end)
  end
end

---@class LayoutOpts
---@field ranged boolean
---@field unlinked boolean
---@field discussion_id string|nil
---@field reply boolean|nil

---This function sets up the layout and popups needed to create a comment, note and
---multi-line comment. It also sets up the basic keybindings for switching between
---window panes, and for the non-primary sections.
---@param opts LayoutOpts
---@return NuiLayout
M.create_comment_layout = function(opts)
  local popup_settings = state.settings.popup
  local title
  local user_settings
  if opts.discussion_id ~= nil then
    title = "Reply"
    user_settings = popup_settings.reply
  elseif opts.unlinked then
    title = "Note"
    user_settings = popup_settings.note
  else
    title = "Comment"
    user_settings = popup_settings.comment
  end
  local settings = u.merge(popup_settings, user_settings or {})

  M.current_win = vim.api.nvim_get_current_win()
  M.comment_popup = Popup(popup.create_popup_state(title, settings))
  M.draft_popup = Popup(popup.create_box_popup_state("Draft", false, settings))
  M.start_line, M.end_line = u.get_visual_selection_boundaries()

  local internal_layout = Layout.Box({
    Layout.Box(M.comment_popup, { grow = 1 }),
    Layout.Box(M.draft_popup, { size = 3 }),
  }, { dir = "col" })

  local layout = Layout({
    position = settings.position,
    relative = "editor",
    size = {
      width = settings.width,
      height = settings.height,
    },
  }, internal_layout)

  popup.set_cycle_popups_keymaps({ M.comment_popup, M.draft_popup })
  popup.set_up_autocommands(M.comment_popup, layout, M.current_win)

  local range = opts.ranged and { start_line = M.start_line, end_line = M.end_line } or nil
  local unlinked = opts.unlinked or false

  ---Keybinding for focus on draft section
  popup.set_popup_keymaps(M.draft_popup, function()
    local text = u.get_buffer_text(M.comment_popup.bufnr)
    confirm_create_comment(text, range, unlinked, opts.discussion_id)
    vim.api.nvim_set_current_win(M.current_win)
  end, miscellaneous.toggle_bool, popup.non_editable_popup_opts)

  ---Keybinding for focus on text section
  popup.set_popup_keymaps(M.comment_popup, function(text)
    confirm_create_comment(text, range, unlinked, opts.discussion_id)
    vim.api.nvim_set_current_win(M.current_win)
  end, miscellaneous.attach_file, popup.editable_popup_opts)

  vim.schedule(function()
    local draft_mode = state.settings.discussion_tree.draft_mode
    vim.api.nvim_buf_set_lines(M.draft_popup.bufnr, 0, -1, false, { u.bool_to_string(draft_mode) })
  end)

  return layout
end

--- This function will open a comment popup in order to create a comment on the changed/updated
--- line in the current MR
M.create_comment = function()
  if not M.can_create_comment(false) then
    return
  end

  local layout = M.create_comment_layout({ ranged = false, unlinked = false })
  layout:mount()
end

--- This function will open a multi-line comment popup in order to create a multi-line comment
--- on the changed/updated line in the current MR
M.create_multiline_comment = function()
  if not M.can_create_comment(true) then
    u.press_escape()
    return
  end

  local layout = M.create_comment_layout({ ranged = true, unlinked = false })
  layout:mount()
end

--- This function will open a a popup to create a "note" (e.g. unlinked comment)
--- on the changed/updated line in the current MR
M.create_note = function()
  local layout = M.create_comment_layout({ ranged = false, unlinked = true })
  layout:mount()
end

---Given the current visually selected area of text, builds text to fill in the
---comment popup with a suggested change
---@return LineRange|nil
---@return integer
local build_suggestion = function()
  local current_line = vim.api.nvim_win_get_cursor(0)[1]
  M.start_line, M.end_line = u.get_visual_selection_boundaries()

  local range_length = M.end_line - M.start_line
  local backticks = "```"
  local selected_lines = u.get_lines(M.start_line, M.end_line)

  for _, line in ipairs(selected_lines) do
    if string.match(line, "^```%S*$") then
      backticks = "````"
      break
    end
  end

  local suggestion_start
  if M.start_line == current_line then
    suggestion_start = backticks .. "suggestion:-0+" .. range_length
  elseif M.end_line == current_line then
    suggestion_start = backticks .. "suggestion:-" .. range_length .. "+0"
  else
    --- This should never happen afaik
    u.notify("Unexpected suggestion position", vim.log.levels.ERROR)
    return nil, 0
  end
  suggestion_start = suggestion_start
  local suggestion_lines = {}
  table.insert(suggestion_lines, suggestion_start)
  vim.list_extend(suggestion_lines, selected_lines)
  table.insert(suggestion_lines, backticks)

  return suggestion_lines, range_length
end

--- This function will open a a popup to create a suggestion comment
--- on the changed/updated line in the current MR
--- See: https://docs.gitlab.com/ee/user/project/merge_requests/reviews/suggestions.html
M.create_comment_suggestion = function()
  if not M.can_create_comment(true) then
    u.press_escape()
    return
  end

  local suggestion_lines, range_length = build_suggestion()

  local layout = M.create_comment_layout({ ranged = range_length > 0, unlinked = false })
  layout:mount()

  vim.schedule(function()
    if suggestion_lines then
      vim.api.nvim_buf_set_lines(M.comment_popup.bufnr, 0, -1, false, suggestion_lines)
    end
  end)
end

---Returns true if it's possible to create an Inline Comment
---@param must_be_visual boolean True if current mode must be visual
---@return boolean
M.can_create_comment = function(must_be_visual)
  -- Check that diffview is initialized
  if reviewer.tabnr == nil then
    u.notify("Reviewer must be initialized first", vim.log.levels.ERROR)
    return false
  end

  -- Check that we are in the Diffview tab
  local tabnr = vim.api.nvim_get_current_tabpage()
  if tabnr ~= reviewer.tabnr then
    u.notify("Comments can only be left in the reviewer pane", vim.log.levels.ERROR)
    return false
  end

  -- Check that we are hovering over the code
  local filetype = vim.bo[0].filetype
  if filetype == "DiffviewFiles" or filetype == "gitlab" then
    u.notify(
      "Comments can only be left on the code. To leave unlinked comments, use gitlab.create_note() instead",
      vim.log.levels.ERROR
    )
    return false
  end

  -- Check that the file has not been renamed
  if reviewer.is_file_renamed() and not reviewer.does_file_have_changes() then
    u.notify("Commenting on (unchanged) renamed or moved files is not supported", vim.log.levels.ERROR)
    return false
  end

  -- Check that we are in a valid buffer
  if not M.sha_exists() then
    return false
  end

  -- Check that there aren't saved modifications
  local file = reviewer.get_current_file_path()
  if file == nil then
    return false
  end
  local has_changes, err = git.has_changes(file)
  if err ~= nil then
    return false
  end
  -- Check that there aren't unsaved modifications
  local is_modified = vim.bo[0].modified
  if state.settings.reviewer_settings.diffview.imply_local and (is_modified or has_changes) then
    u.notify("Cannot leave comments on changed files, please stash or commit and push", vim.log.levels.ERROR)
    return false
  end

  -- Check we're in visual mode for code suggestions and multiline comments
  if must_be_visual and not u.check_visual_mode() then
    return false
  end

  return true
end

---Checks to see whether you are commenting on a valid buffer. The Diffview plugin names non-existent
---buffers as 'null'
---@return boolean
M.sha_exists = function()
  if vim.fn.expand("%") == "diffview://null" then
    u.notify("This file does not exist, please comment on the other buffer", vim.log.levels.ERROR)
    return false
  end
  return true
end

return M
