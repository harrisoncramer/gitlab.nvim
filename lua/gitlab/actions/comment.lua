-- This module is responsible for creating new comments
-- in the reviewer's buffer. The reviewer will pass back
-- to this module the data required to make the API calls
local Popup              = require("nui.popup")
local state              = require("gitlab.state")
local job                = require("gitlab.job")
local u                  = require("gitlab.utils")
local discussions        = require("gitlab.actions.discussions")
local reviewer           = require("gitlab.reviewer")
local M                  = {}

local comment_popup      = Popup(u.create_popup_state("Comment", "40%", "60%"))
local note_popup         = Popup(u.create_popup_state("Note", "40%", "60%"))

-- This function will open a comment popup in order to create a comment on the changed/updated line in the current MR
M.create_comment         = function()
  comment_popup:mount()
  state.set_popup_keymaps(comment_popup, function(text)
    M.confirm_create_comment(text)
  end)
end

M.create_note            = function()
  note_popup:mount()
  state.set_popup_keymaps(note_popup, function(text)
    M.confirm_create_comment(text, true)
  end)
end

-- This function (settings.popup.perform_action) will send the comment to the Go server
M.confirm_create_comment = function(text, unlinked)
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
    type = "modification"
  }

  job.run_job("/comment", "POST", body, function(data)
    vim.notify("Comment created!", vim.log.levels.INFO)
    discussions.add_discussion({ data = data, unlinked = false })
  end)
end

return M
