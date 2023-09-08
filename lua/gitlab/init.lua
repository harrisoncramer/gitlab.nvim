local u                       = require("gitlab.utils")
local async                   = require("gitlab.async")
local server                  = require("gitlab.server")
local state                   = require("gitlab.state")
local reviewer                = require("gitlab.reviewer")
local discussions             = require("gitlab.actions.discussions")
local summary                 = require("gitlab.actions.summary")
local assignees_and_reviewers = require("gitlab.actions.assignees_and_reviewers")
local comment                 = require("gitlab.actions.comment")
local pipeline                = require("gitlab.actions.pipeline")
local approvals               = require("gitlab.actions.approvals")
local miscellaneous           = require("gitlab.actions.miscellaneous")

local info                    = state.dependencies.info
local project_members         = state.dependencies.project_members
local revisions               = state.dependencies.revisions

return {
  setup              = function(args)
    if args == nil then args = {} end
    server.build()                 -- Builds the Go binary if it doesn't exist
    state.setPluginConfiguration() -- Sets configuration from `.gitlab.nvim` file
    state.merge_settings(args)     -- Sets keymaps and other settings from setup function
    reviewer.init()                -- Picks and initializes reviewer (default is Delta)
    u.has_reviewer(args.reviewer or "delta")
  end,
  -- Global Actions 🌎
  summary            = async.sequence({ info }, summary.summary),
  approve            = async.sequence({ info }, approvals.approve),
  revoke             = async.sequence({ info }, approvals.revoke),
  add_reviewer       = async.sequence({ info, project_members }, assignees_and_reviewers.add_reviewer),
  delete_reviewer    = async.sequence({ info, project_members }, assignees_and_reviewers.delete_reviewer),
  add_assignee       = async.sequence({ info, project_members }, assignees_and_reviewers.add_assignee),
  delete_assignee    = async.sequence({ info, project_members }, assignees_and_reviewers.delete_assignee),
  create_comment     = async.sequence({ info, revisions }, comment.create_comment),
  create_note        = async.sequence({ info }, comment.create_note),
  review             = async.sequence({ u.merge(info, { refresh = true }) }, function() reviewer.open() end),
  pipeline           = async.sequence({ info }, pipeline.open),
  -- Discussion Tree Actions 🌴
  toggle_discussions = async.sequence({ info }, discussions.toggle),
  edit_comment       = async.sequence({ info }, discussions.edit_comment),
  delete_comment     = async.sequence({ info }, discussions.delete_comment),
  toggle_resolved    = async.sequence({ info }, discussions.toggle_resolved),
  reply              = async.sequence({ info }, discussions.reply),
  -- Other functions 🤷
  state              = state,
  print_settings     = state.print_settings,
  open_in_browser    = async.sequence({ info }, miscellaneous.open_in_browser),
}
