local u                       = require("gitlab.utils")
local async                   = require("gitlab.async")
local server                  = require("gitlab.server")
local state                   = require("gitlab.state")
local reviewer                = require("gitlab.reviewer")
local discussions             = require("gitlab.actions.discussions")
local summary                 = require("gitlab.actions.summary")
local assignees_and_reviewers = require("gitlab.actions.assignees_and_reviewers")
local comment                 = require("gitlab.actions.comment")
local approvals               = require("gitlab.actions.approvals")

local info                    = state.dependencies.info
local project_members         = state.dependencies.project_members
local revisions               = state.dependencies.revisions

return {
  setup           = function(args)
    server.build()                 -- Builds the Go binary if it doesn't exist
    state.setPluginConfiguration() -- Sets configuration from `.gitlab.nvim` file
    state.merge_settings(args)     -- Sets keymaps and other settings from setup function
  end,
  -- Global Actions 🌎
  summary         = async.sequence(summary.summary, { info }),
  approve         = async.sequence(approvals.approve, { info }),
  revoke          = async.sequence(approvals.revoke, { info }),
  add_reviewer    = async.sequence(assignees_and_reviewers.add_reviewer, { info, project_members }),
  delete_reviewer = async.sequence(assignees_and_reviewers.delete_reviewer, { info, project_members }),
  add_assignee    = async.sequence(assignees_and_reviewers.add_assignee, { info, project_members }),
  delete_assignee = async.sequence(assignees_and_reviewers.delete_assignee, { info, project_members }),
  review          = async.sequence(reviewer.open, { info }),
  create_comment  = async.sequence(comment.create_comment, { info, revisions }),
  -- Discussion Tree Actions 🌴
  edit_comment    = async.sequence(discussions.edit_comment, { info }),
  delete_comment  = async.sequence(discussions.delete_comment, { info }),
  toggle_resolved = async.sequence(discussions.toggle_resolved, { info }),
  reply           = async.sequence(discussions.reply, { info }),
  -- Other functions 🤷
  state           = state,
  print_settings  = state.print_settings,
}
