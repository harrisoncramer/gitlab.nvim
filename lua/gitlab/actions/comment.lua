-- This module is responsible for creating new comments in the reviewer's buffer. The reviewer will
-- pass back to this module the data required to make the API calls.

local Popup = require("nui.popup")
local Layout = require("nui.layout")
local state = require("gitlab.state")
local client = require("gitlab.client")
local u = require("gitlab.utils")
local popup = require("gitlab.popup")
local git = require("gitlab.git")
local hunks = require("gitlab.hunks")
local discussions = require("gitlab.actions.discussions")
local draft_notes = require("gitlab.actions.draft_notes")
local miscellaneous = require("gitlab.actions.miscellaneous")
local reviewer = require("gitlab.reviewer")
local Location = require("gitlab.reviewer.location")

local M = {
  start_line = nil,
  end_line = nil,
  draft_popup = nil,
  comment_popup = nil,
}

---Build a Location from the live reviewer state (the active Diffview session).
---Return nil when the location cannot be built due to missing reviewer data.
---@return Location?
M.new_location_from_reviewer = function()
  local reviewer_data = reviewer.get_reviewer_data()
  if reviewer_data == nil then
    return nil
  end
  local diff_hunks =
    hunks.get_hunks(reviewer_data.old_sha, reviewer_data.new_sha, reviewer_data.old_file_name, reviewer_data.file_name)
  return Location.new(reviewer_data, diff_hunks)
end

---Fire the API to send the comment data to the Go server.
---@param text string comment text
---@param unlinked boolean if true, the comment is not linked to a line
---@param discussion_id? string The ID of the discussion when replying in a thread, otherwise nil
local confirm_create_comment = function(text, unlinked, discussion_id)
  if text == nil then
    u.notify("Reviewer did not provide text of change", vim.log.levels.ERROR)
    return
  end

  local is_draft = M.draft_popup and u.string_to_bool(u.get_buffer_text(M.draft_popup.bufnr))

  -- Creating a normal reply to a discussion
  if discussion_id ~= nil and not is_draft then
    local body = { discussion_id = discussion_id, reply = text, draft = is_draft }
    client.send_request("/mr/reply", "POST", body, function()
      u.notify("Sent reply!", vim.log.levels.INFO)
      discussions.rebuild_view(unlinked)
    end)
    return
  end

  -- Creating a draft reply, in response to a discussion ID
  if discussion_id ~= nil and is_draft then
    local body = { comment = text, discussion_id = discussion_id }
    client.send_request("/mr/draft_notes/", "POST", body, function()
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
    client.send_request(endpoint, "POST", body, function()
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

  local revision = state.MR_REVISIONS[1]
  local position_data = {
    file_name = M.location.reviewer_data.file_name,
    old_file_name = M.location.reviewer_data.old_file_name,
    base_commit_sha = revision.base_commit_sha,
    start_commit_sha = revision.start_commit_sha,
    head_commit_sha = revision.head_commit_sha,
    old_line = M.location.location_data.old_line,
    new_line = M.location.location_data.new_line,
    line_range = M.location.location_data.line_range,
  }

  -- Creating a new comment (linked to specific changes)
  local body = u.merge({ type = "text", comment = text }, position_data)
  local endpoint = is_draft and "/mr/draft_notes/" or "/mr/comment"
  client.send_request(endpoint, "POST", body, function()
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

---Send comment deletion request to the Go server and re-render the tree.
---@param note_id integer
---@param discussion_id string
---@param unlinked boolean
M.confirm_delete_comment = function(note_id, discussion_id, unlinked)
  local body = { discussion_id = discussion_id, note_id = tonumber(note_id) }
  client.send_request("/mr/comment", "DELETE", body, function(data)
    u.notify(data.message, vim.log.levels.INFO)
    discussions.rebuild_view(unlinked)
  end)
end

---Send edited comment to the Go server.
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
    client.send_request("/mr/comment", "PATCH", body, function(data)
      u.notify(data.message, vim.log.levels.INFO)
      discussions.rebuild_view(unlinked)
    end)
  end
end

---@class LayoutOpts
---@field unlinked boolean
---@field discussion_id? string
---@field reply? boolean
---@field file_name? string

---Set up the layout and popups needed to create a comment, note and multi-line comment.
---Also set up basic keybindings for the non-primary sections, and for switching between
---sections.
---@param opts LayoutOpts
---@return NuiLayout
M.create_comment_layout = function(opts)
  local popup_settings = state.settings.popup
  local title
  local user_settings
  if opts.discussion_id ~= nil then
    title = "Reply" .. (opts.file_name and string.format(" [%s]", opts.file_name) or "")
    user_settings = popup_settings.reply
  elseif opts.unlinked then
    title = "Note"
    user_settings = popup_settings.note
  else
    local file_name = (M.location.reviewer_data.new_file_focused or M.location.reviewer_data.old_file_name == "")
        and M.location.reviewer_data.file_name
      or M.location.reviewer_data.old_file_name
    title =
      popup.create_title("Comment", file_name, M.location.reviewer_data.start_line, M.location.reviewer_data.end_line)
    user_settings = popup_settings.comment
  end
  local settings = u.merge(popup_settings, user_settings or {})

  local current_win = vim.api.nvim_get_current_win()
  M.comment_popup = Popup(popup.create_popup_state({ title = title, user_settings = settings }))
  M.draft_popup = Popup(popup.create_box_popup_state("Draft", false, settings))

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
  popup.set_up_autocommands(M.comment_popup, layout, current_win)

  local unlinked = opts.unlinked or false

  ---Keybinding for focus on draft section
  popup.set_popup_keymaps(M.draft_popup, function()
    local text = u.get_buffer_text(M.comment_popup.bufnr)
    confirm_create_comment(text, unlinked, opts.discussion_id)
    vim.api.nvim_set_current_win(current_win)
  end, miscellaneous.toggle_bool, popup.non_editable_popup_opts)

  ---Keybinding for focus on text section
  popup.set_popup_keymaps(M.comment_popup, function(text)
    confirm_create_comment(text, unlinked, opts.discussion_id)
    vim.api.nvim_set_current_win(current_win)
  end, miscellaneous.attach_file, popup.editable_popup_opts)

  vim.schedule(function()
    local draft_mode = state.settings.discussion_tree.draft_mode
    vim.api.nvim_buf_set_lines(M.draft_popup.bufnr, 0, -1, false, { u.bool_to_string(draft_mode) })
  end)

  return layout
end

---Open a comment popup in order to create a comment on the changed/updated line in the
---current MR.
M.create_comment = function()
  M.location = M.new_location_from_reviewer()
  if not M.can_create_comment(false) then
    return
  end

  local layout = M.create_comment_layout({ unlinked = false })
  layout:mount()
end

---Open a multi-line comment popup in order to create a multi-line comment on the
---changed/updated line in the current MR.
M.create_multiline_comment = function()
  M.location = M.new_location_from_reviewer()
  if not M.can_create_comment(true) then
    u.press_escape()
    return
  end

  local layout = M.create_comment_layout({ unlinked = false })
  layout:mount()
end

---Open a popup to create a "note" (e.g. unlinked comment) on the changed/updated line
---in the current MR.
M.create_note = function()
  local layout = M.create_comment_layout({ unlinked = true })
  layout:mount()
end

---Given the current visually selected area of text, builds text to fill in the
---comment popup with a suggested change
---@return string[]?
local build_suggestion = function()
  local current_line = vim.api.nvim_win_get_cursor(0)[1]
  local range_length = M.location.reviewer_data.end_line - M.location.reviewer_data.start_line
  local backticks = "```"
  local selected_lines = u.get_lines(M.location.reviewer_data.start_line, M.location.reviewer_data.end_line)

  for _, line in ipairs(selected_lines) do
    if string.match(line, "^```%S*$") then
      backticks = "````"
      break
    end
  end

  local suggestion_start
  if M.location.reviewer_data.start_line == current_line then
    suggestion_start = backticks .. "suggestion:-0+" .. range_length
  elseif M.location.reviewer_data.end_line == current_line then
    suggestion_start = backticks .. "suggestion:-" .. range_length .. "+0"
  else
    --- This should never happen afaik
    u.notify("Unexpected suggestion position", vim.log.levels.ERROR)
    return nil
  end
  suggestion_start = suggestion_start
  local suggestion_lines = {}
  table.insert(suggestion_lines, suggestion_start)
  vim.list_extend(suggestion_lines, selected_lines)
  table.insert(suggestion_lines, backticks)

  return suggestion_lines
end

---Open a popup to create a suggestion comment on the changed/updated line in the current MR
---See: https://docs.gitlab.com/ee/user/project/merge_requests/reviews/suggestions.html
M.create_comment_suggestion = function()
  M.location = M.new_location_from_reviewer()
  if not M.can_create_comment(true) then
    u.press_escape()
    return
  end

  local suggestion_lines = build_suggestion()

  local layout = M.create_comment_layout({ unlinked = false })
  layout:mount()

  vim.schedule(function()
    if suggestion_lines then
      vim.api.nvim_buf_set_lines(M.comment_popup.bufnr, 0, -1, false, suggestion_lines)
    end
  end)
end

---Return true if it's possible to create an inline comment.
---@param must_be_visual boolean True if current mode must be visual
---@return boolean
M.can_create_comment = function(must_be_visual)
  -- Check that diffview is initialized
  if reviewer.tabid == nil then
    u.notify("Reviewer must be initialized first", vim.log.levels.ERROR)
    return false
  end

  -- Check that we are in the Diffview tab
  local tabid = vim.api.nvim_get_current_tabpage()
  if tabid ~= reviewer.tabid then
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

  if not git.check_current_branch_up_to_date_on_remote(vim.log.levels.ERROR) then
    return false
  end

  -- Check we're in visual mode for code suggestions and multiline comments
  if must_be_visual and not u.check_visual_mode() then
    return false
  end

  if M.location == nil then
    u.notify("Error getting location information", vim.log.levels.ERROR)
    return false
  end

  return true
end

---Check whether user is commenting on a valid buffer.
---Tightly coupled to how the Diffview plugin names non-existent buffers!
---@return boolean
M.sha_exists = function()
  if vim.fn.expand("%") == "diffview://null" then
    u.notify("This file does not exist, please comment on the other buffer", vim.log.levels.ERROR)
    return false
  end
  return true
end

return M
