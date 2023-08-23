-- This module is responsible for creating new comments
-- in the reviewer's buffer. The reviewer will pass back
-- to this module the data required to make the API calls
local Popup              = require("nui.popup")
local state              = require("gitlab.state")
local u                  = require("gitlab.utils")
local discussions        = require("gitlab.actions.discussions")
local reviewer           = require("gitlab.reviewer")
local M                  = {}

local comment_popup      = Popup(u.create_popup_state("Comment", "40%", "60%"))

-- This function will open a comment popup in order to create a comment on the changed/updated line in the current MR
M.create_comment         = function()
  comment_popup:mount()
  state.set_popup_keymaps(comment_popup, M.confirm_create_comment)
end

-- This function (settings.popup.perform_action) will send the comment to the Go server
M.confirm_create_comment = function(text)
  local file_name, line_numbers = reviewer.get_changes()

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
  local jsonTable = {
    comment = text,
    file_name = file_name,
    old_line = line_numbers.old_line,
    new_line = line_numbers.new_line,
    base_commit_sha = revision.base_commit_sha,
    start_commit_sha = revision.start_commit_sha,
    head_commit_sha = revision.head_commit_sha,
    type = "modification"
  }

  local json = vim.json.encode(jsonTable)

  job.run_job("comment", "POST", json, function(data)
    vim.notify("Comment created")
    discussions.refresh_tree()
  end)
end

return M
