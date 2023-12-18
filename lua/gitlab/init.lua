local u = require("gitlab.utils")
local async = require("gitlab.async")
local server = require("gitlab.server")
local state = require("gitlab.state")
local reviewer = require("gitlab.reviewer")
local discussions = require("gitlab.actions.discussions")
local merge = require("gitlab.actions.merge")
local summary = require("gitlab.actions.summary")
local assignees_and_reviewers = require("gitlab.actions.assignees_and_reviewers")
local comment = require("gitlab.actions.comment")
local pipeline = require("gitlab.actions.pipeline")
local create_mr = require("gitlab.actions.create_mr")
local approvals = require("gitlab.actions.approvals")
local miscellaneous = require("gitlab.actions.miscellaneous")

local info = state.dependencies.info
local project_members = state.dependencies.project_members
local revisions = state.dependencies.revisions

return {
  setup = function(args)
    if args == nil then
      args = {}
    end
    server.build() -- Builds the Go binary if it doesn't exist
    state.merge_settings(args) -- Sets keymaps and other settings from setup function
    require("gitlab.colors") -- Sets colors
    reviewer.init()
    discussions.initialize_discussions() -- place signs / diagnostics for discussions in reviewer
  end,
  -- Global Actions 🌎
  summary = async.sequence({ u.merge(info, { refresh = true }) }, summary.summary),
  approve = async.sequence({ info }, approvals.approve),
  revoke = async.sequence({ info }, approvals.revoke),
  add_reviewer = async.sequence({ info, project_members }, assignees_and_reviewers.add_reviewer),
  delete_reviewer = async.sequence({ info, project_members }, assignees_and_reviewers.delete_reviewer),
  add_assignee = async.sequence({ info, project_members }, assignees_and_reviewers.add_assignee),
  delete_assignee = async.sequence({ info, project_members }, assignees_and_reviewers.delete_assignee),
  create_comment = async.sequence({ info, revisions }, comment.create_comment),
  create_multiline_comment = async.sequence({ info, revisions }, comment.create_multiline_comment),
  create_comment_suggestion = async.sequence({ info, revisions }, comment.create_comment_suggestion),
  move_to_discussion_tree_from_diagnostic = async.sequence({}, discussions.move_to_discussion_tree),
  create_note = async.sequence({ info }, comment.create_note),
  create_mr = async.sequence({}, create_mr.start),
  review = async.sequence({ u.merge(info, { refresh = true }), revisions }, function()
    reviewer.open()
  end),
  close_review = function()
    reviewer.close()
  end,
  pipeline = async.sequence({ info }, pipeline.open),
  merge = async.sequence({ u.merge(info, { refresh = true }) }, merge.merge),
  -- Discussion Tree Actions 🌴
  toggle_discussions = async.sequence({ info }, discussions.toggle),
  edit_comment = async.sequence({ info }, discussions.edit_comment),
  delete_comment = async.sequence({ info }, discussions.delete_comment),
  toggle_resolved = async.sequence({ info }, discussions.toggle_discussion_resolved),
  reply = async.sequence({ info }, discussions.reply),
  -- Other functions 🤷
  state = state,
  print_settings = state.print_settings,
  open_in_browser = async.sequence({ info }, miscellaneous.open_in_browser),
}
