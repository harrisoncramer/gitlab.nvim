--- This module is responsible for creating new comments
--- in the reviewer's buffer. The reviewer will pass back
--- to this module the data required to make the API calls
local List = require("gitlab.utils.list")
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

local M = {
  current_win = nil,
  start_line = nil,
  end_line = nil,
  draft_popup = nil,
  comment_popup = nil,
}

M.rebuild_view = function(unlinked)
  discussions.refresh(function()
    if unlinked then
      discussions.rebuild_unlinked_discussion_tree()
    else
      discussions.rebuild_discussion_tree()
    end
  end)
end

---Fires the API that sends the comment data to the Go server, called when you "confirm" creation
---via the M.settings.popup.perform_action keybinding
---@param text string comment text
---@param visual_range LineRange | nil range of visual selection or nil
---@param unlinked boolean | nil if true, the comment is not linked to a line
---@param discussion_id string | nil The ID of the discussion to which the reply is responding, nil if not a reply
local confirm_create_comment = function(text, visual_range, unlinked, discussion_id)
  if text == nil then
    u.notify("Reviewer did not provide text of change", vim.log.levels.ERROR)
    return
  end

  local is_draft = M.draft_popup and u.string_to_bool(u.get_buffer_text(M.draft_popup.bufnr))

  -- Creating a reply to a discussion
  if discussion_id ~= nil then
    local body = { discussion_id = discussion_id, reply = text, draft = is_draft }
    job.run_job("/mr/reply", "POST", body, function(data)
      u.notify("Sent reply!", vim.log.levels.INFO)
      discussions.add_reply_to_tree(data.note, discussion_id, false)
      discussions.load_discussions()
    end)
    return
  end

  -- Creating a note (unlinked comment)
  if unlinked then
    local body = { comment = text }
    local endpoint = is_draft and "/mr/draft_notes/" or "/mr/comment"
    job.run_job(endpoint, "POST", body, function(data)
      u.notify(is_draft and "Draft note created!" or "Note created!", vim.log.levels.INFO)
      M.rebuild_view(unlinked)
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

  -- Creating a comment (linked to specific changes)
  local endpoint = is_draft and "/mr/draft_notes/" or "/mr/comment"
  job.run_job(endpoint, "POST", body, function(data)
    u.notify(is_draft and "Draft comment created!" or "Comment created!", vim.log.levels.INFO)
    if is_draft then
      draft_notes.add_draft_note({ draft_note = data.draft_note, unlinked = false })
      discussions.refresh()
    else
      M.rebuild_view(unlinked)
    end
  end)
end

-- This function will actually send the deletion to Gitlab when you make a selection,
-- and re-render the tree
---@param note_id integer
---@param discussion_id string
M.send_deletion = function(note_id, discussion_id)
  local body = { discussion_id = discussion_id, note_id = tonumber(note_id) }
  job.run_job("/mr/comment", "DELETE", body, function(data)
    u.notify(data.message, vim.log.levels.INFO)

    local has_position = List.new(state.DISCUSSION_DATA.discussions):find(function(d)
      if d.id ~= discussion_id then
        return true
      end
    end) ~= nil

    M.rebuild_view(not has_position)
  end)
end

---This function sends the edited comment to the Go server
---@param discussion_id string
---@param note_id integer
---@param unlinked boolean
M.send_edits = function(discussion_id, note_id, unlinked)
  return function(text)
    local body = {
      discussion_id = discussion_id,
      note_id = note_id,
      comment = text,
    }
    job.run_job("/mr/comment", "PATCH", body, function(data)
      u.notify(data.message, vim.log.levels.INFO)
      M.rebuild_view(unlinked)
    end)
  end
end

---@class LayoutOpts
---@field ranged boolean
---@field discussion_id string|nil
---@field unlinked boolean

---This function sets up the layout and popups needed to create a comment, note and
---multi-line comment. It also sets up the basic keybindings for switching between
---window panes, and for the non-primary sections.
---@param opts LayoutOpts|nil
---@return NuiLayout
M.create_comment_layout = function(opts)
  if opts == nil then
    opts = {}
  end

  M.current_win = vim.api.nvim_get_current_win()
  local title = opts.discussion_id and "Reply" or "Comment"
  local settings = opts.discussion_id ~= nil and state.settings.popup.reply or state.settings.popup.comment

  M.comment_popup = Popup(u.create_popup_state(title, settings))
  M.draft_popup = Popup(u.create_box_popup_state("Draft", false))
  M.start_line, M.end_line = u.get_visual_selection_boundaries()

  local internal_layout = Layout.Box({
    Layout.Box(M.comment_popup, { grow = 1 }),
    Layout.Box(M.draft_popup, { size = 3 }),
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

  miscellaneous.set_cycle_popups_keymaps({ M.comment_popup, M.draft_popup })

  local range = opts.ranged and { start_line = M.start_line, end_line = M.end_line } or nil
  local unlinked = opts.unlinked or false

  ---Keybinding for focus on text section
  state.set_popup_keymaps(M.draft_popup, function()
    local text = u.get_buffer_text(M.comment_popup.bufnr)
    confirm_create_comment(text, range, unlinked, opts.discussion_id)
    vim.api.nvim_set_current_win(opts.discussion_id == nil and M.current_win or discussions.split.winid)
  end, miscellaneous.toggle_bool, popup_opts)

  ---Keybinding for focus on draft section
  state.set_popup_keymaps(M.comment_popup, function(text)
    confirm_create_comment(text, range, unlinked, opts.discussion_id)
    vim.api.nvim_set_current_win(opts.discussion_id == nil and M.current_win or discussions.split.winid)
  end, miscellaneous.attach_file, popup_opts)

  vim.schedule(function()
    local draft_mode = state.settings.discussion_tree.draft_mode
    vim.api.nvim_buf_set_lines(M.draft_popup.bufnr, 0, -1, false, { u.bool_to_string(draft_mode) })
  end)

  return layout
end

--- This function will open a comment popup in order to create a comment on the changed/updated
--- line in the current MR
M.create_comment = function()
  local has_clean_tree, err = git.has_clean_tree()
  if err ~= nil then
    return
  end
  local is_modified = vim.api.nvim_buf_get_option(0, "modified")
  if state.settings.reviewer_settings.diffview.imply_local and (is_modified or not has_clean_tree) then
    u.notify(
      "Cannot leave comments on changed files. \n Please stash all local changes or push them to the feature branch.",
      vim.log.levels.WARN
    )
    return
  end

  if not M.sha_exists() then
    return
  end

  local layout = M.create_comment_layout()
  layout:mount()
end

--- This function will open a multi-line comment popup in order to create a multi-line comment
--- on the changed/updated line in the current MR
M.create_multiline_comment = function()
  if not u.check_visual_mode() then
    return
  end
  if not M.sha_exists() then
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

  for line in ipairs(selected_lines) do
    if string.match(line, "^```$") then
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
  if not u.check_visual_mode() then
    return
  end
  if not M.sha_exists() then
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
