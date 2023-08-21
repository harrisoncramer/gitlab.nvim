local Popup              = require("nui.popup")
local job                = require("gitlab.job")
local state              = require("gitlab.state")
local u                  = require("gitlab.utils")
local discussions        = require("gitlab.discussions")
local settings           = require("gitlab.settings")
local M                  = {}

local comment_popup      = Popup(u.create_popup_state("Comment", "40%", "60%"))

-- This function will open a comment popup in order to create a comment on the changed/updated line in the current MR
M.create_comment         = function()
  if vim.api.nvim_get_current_win() ~= u.get_win_from_buf(state.REVIEW_BUF) then
    vim.notify("You must leave comments in the review panel, please call require('gitlab').review()",
      vim.log.levels.ERROR)
    return
  end

  comment_popup:mount()
  settings.set_popup_keymaps(comment_popup, M.confirm_create_comment)
end

-- This function (settings.popup.perform_action) will send the comment to the Go server
M.confirm_create_comment = function(text)
  local line_num = u.get_current_line_number()
  local content = u.get_line_content(state.REVIEW_BUF, line_num)
  local current_line_changes = discussions.get_change_nums(content)
  local new_line = u.get_line_content(state.REVIEW_BUF, line_num + 1)
  local next_line_changes = discussions.get_change_nums(new_line)

  -- This is actually a modified line if these conditions are met
  if (current_line_changes.old_line and not current_line_changes.new_line and not next_line_changes.old_line and next_line_changes.new_line) then
    do
      current_line_changes = {
        old_line = current_line_changes.old,
        new_line = next_line_changes.new_line
      }
    end
  end

  local count = 0
  for _ in pairs(current_line_changes) do
    count = count + 1
  end

  if count == 0 then
    vim.notify("Cannot comment on invalid line", vim.log.levels.ERROR)
  end

  local file_name = discussions.get_file_from_review_buffer(line_num)
  if file_name == nil then
    vim.notify("Could not detect file name from review pane", vim.log.levels.ERROR)
  end

  local revision = state.MR_REVISIONS[1]
  local jsonTable = {
    comment = text,
    file_name = file_name,
    old_line = current_line_changes.old_line,
    new_line = current_line_changes.new_line,
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
