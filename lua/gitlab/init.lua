local async                   = require("gitlab.async")
local server                  = require("gitlab.server")
local state                   = require("gitlab.state")
local reviewer                = require("gitlab.reviewer")
local u                       = require("gitlab.utils")
local discussions             = require("gitlab.actions.discussions")
local summary                 = require("gitlab.actions.summary")
local assignees_and_reviewers = require("gitlab.actions.assignees_and_reviewers")
local comment                 = require("gitlab.actions.comment")
local approvals               = require("gitlab.actions.approvals")

local M                       = {}

M.setup                       = function(args)
  if not u.has_delta() then
    vim.notify("Please install delta to use gitlab.nvim!", vim.log.levels.ERROR)
    return
  end

  local file_path = u.current_file_path()
  local parent_dir = vim.fn.fnamemodify(file_path, ":h:h:h:h")
  state.settings.bin_path = parent_dir
  state.settings.bin = parent_dir .. "/bin"

  local binary_exists = vim.loop.fs_stat(state.settings.bin)
  if binary_exists == nil then server.build() end

  state.setPluginConfiguration() -- Sets configuration from `.gitlab.nvim` file
  state.merge_settings(args)     -- Sets keymaps and other settings from setup function
end

-- Dependencies
-- These tables are passed to the async.sequence function, which calls them in sequence
-- before calling an action. They are used to set global state that's required
-- for each of the actions to occur.
local info                    = { endpoint = "/info", key = "info", state = "INFO" }
local revisions               = { endpoint = "/mr/revisions", key = "Revisions", state = "MR_REVISIONS" }
local project_members         = { endpoint = "/members", key = "ProjectMembers", state = "PROJECT_MEMBERS" }

-- Global Actions 🌎
-- These actions can be called from anywhere in Neovim
M.summary                     = async.sequence(summary.summary, { info })
M.approve                     = async.sequence(approvals.approve, { info })
M.revoke                      = async.sequence(approvals.revoke, { info })
M.add_reviewer                = async.sequence(assignees_and_reviewers.add_reviewer, { info, project_members })
M.delete_reviewer             = async.sequence(assignees_and_reviewers.delete_reviewer, { info, project_members })
M.add_assignee                = async.sequence(assignees_and_reviewers.add_assignee, { info, project_members })
M.delete_assignee             = async.sequence(assignees_and_reviewers.delete_assignee, { info, project_members })

M.review                      = async.sequence(reviewer.open, { info })
M.create_comment              = async.sequence(comment.create_comment, { info, revisions })

-- Discussion Tree Actions
-- These functions are triggered via keybindings on the discussion tree
M.edit_comment                = async.sequence(discussions.edit_comment, { info })
M.delete_comment              = async.sequence(discussions.delete_comment, { info })
M.toggle_resolved             = async.sequence(discussions.toggle_resolved, { info })
M.reply                       = async.sequence(discussions.reply, { info })


M.state = state

return M
