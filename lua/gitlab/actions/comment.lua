-- This module is responsible for creating new comments
-- in the reviewer's buffer. The reviewer will pass back
-- to this module the data required to make the API calls
local Popup         = require("nui.popup")
local state         = require("gitlab.state")
local job           = require("gitlab.job")
local u             = require("gitlab.utils")
local discussions   = require("gitlab.actions.discussions")
local miscellaneous = require("gitlab.actions.miscellaneous")
local reviewer      = require("gitlab.reviewer")
local M             = {}

local comment_popup = Popup(u.create_popup_state("Comment", "40%", "60%"))
local note_popup    = Popup(u.create_popup_state("Note", "40%", "60%"))

-- This function will open a comment popup in order to create a comment on the changed/updated line in the current MR
M.create_comment = function()
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
  local start_line, end_line = u.get_visual_selection_boundries()
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
  local start_line, end_line = u.get_visual_selection_boundries()
  local current_line = vim.api.nvim_win_get_cursor(0)[1]
  local range = end_line - start_line
  local backticks = "```"
  local selected_lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)

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
    vim.notify("Unexpected suggestion position", vim.log.levels.ERROR)
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
  note_popup:mount()
  state.set_popup_keymaps(note_popup, function(text)
    M.confirm_create_comment(text, nil, true)
  end, miscellaneous.attach_file)
end

---@class LineRange
---@field start_line integer
---@field end_line integer

---This function (settings.popup.perform_action) will send the comment to the Go server
---@param text string comment text
---@param range LineRange | nil range of visuel selection or nil
---@param unlinked any
M.confirm_create_comment = function(text, range, unlinked)
  if unlinked then
    local body = { comment = text }
    job.run_job("/comment", "POST", body, function(data)
      vim.notify("Note created!", vim.log.levels.INFO)
      discussions.add_discussion({ data = data, unlinked = true })
    end)
    return
  end

  local file_name, line_numbers, error = reviewer.get_location()

  if error then
    vim.notify(error, vim.log.levels.ERROR)
    return
  end

  if file_name == nil then
    vim.notify("Reviewer did not provide file name", vim.log.levels.ERROR)
    return
  end

  if line_numbers == nil then
    vim.notify("Reviewer did not provide line numbers of change", vim.log.levels.ERROR)
    return
  end

  if text == nil then
    vim.notify("Reviewer did not provide text of change", vim.log.levels.ERROR)
    return
  end

  local revision = state.MR_REVISIONS[1]
  local body = {
    comment = text,
    file_name = file_name,
    old_line = line_numbers.old_line,
    new_line = line_numbers.new_line,
    base_commit_sha = revision.base_commit_sha,
    start_commit_sha = revision.start_commit_sha,
    head_commit_sha = revision.head_commit_sha,
    type = "text",
  }

  local hunks = u.parse_hunk_headers(file_name, state.INFO.target_branch)

  if range then
    -- https://docs.gitlab.com/ee/api/discussions.html#parameters-for-multiline-comments
    -- lua does not have sha1 function built in - there are external dependencies but we can also
    -- calculate this in go server.
    if not hunks then
      vim.notify("Could not parse hunks", vim.log.levels.ERROR)
      return
    end

    --TODO: is this correct also for delta ?
    local is_new = line_numbers.old_line == nil
    local start_selection = u.get_lines_from_hunks(hunks, range.start_line, is_new)
    local end_selection = u.get_lines_from_hunks(hunks, range.end_line, is_new)
    local type = is_new and "new" or "old"
    body.line_range = {
      start = {
        old_line = start_selection.old_line,
        new_line = start_selection.new_line,
        type = type,
      },
      ["end"] = {
        old_line = end_selection.old_line,
        new_line = end_selection.new_line,
        type = type,
      },
    }
    -- Even multiline comment must specify both old line and new line if these are outside of
    -- changed lines.
    if line_numbers.old_line == start_selection.old_line and not start_selection.in_hunk then
      body.new_line = start_selection.new_line
    elseif line_numbers.old_line == end_selection.old_line and not end_selection.in_hunk then
      body.new_line = end_selection.new_line
    elseif line_numbers.new_line == start_selection.new_line and not start_selection.in_hunk then
      body.old_line = start_selection.old_line
    elseif line_numbers.new_line == end_selection.new_line and not end_selection.in_hunk then
      body.old_line = end_selection.old_line
    end
  else
    local line_info = nil
    if line_numbers.old_line == nil then
      line_info = u.get_lines_from_hunks(hunks, line_numbers.new_line, true)
    elseif line_numbers.new_line == nil then
      line_info = u.get_lines_from_hunks(hunks, line_numbers.old_line, false)
    end

    -- If single line comment is outside of changed lines then we need to specify both new line and old line
    -- otherwise the API returns error.
    -- https://docs.gitlab.com/ee/api/discussions.html#create-a-new-thread-in-the-merge-request-diff
    if line_info ~= nil and not line_info.in_hunk then
      body.old_line = line_info.old_line
      body.new_line = line_info.new_line
    end
  end

  job.run_job("/comment", "POST", body, function(data)
    vim.notify("Comment created!", vim.log.levels.INFO)
    discussions.add_discussion({ data = data, unlinked = false })
  end)
end

return M
