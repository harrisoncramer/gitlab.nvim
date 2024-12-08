require("gitlab.utils.list")
local u = require("gitlab.utils")
local async = require("gitlab.async")
local server = require("gitlab.server")
local emoji = require("gitlab.emoji")
local state = require("gitlab.state")
local reviewer = require("gitlab.reviewer")
local discussions = require("gitlab.actions.discussions")
local merge_requests = require("gitlab.actions.merge_requests")
local merge = require("gitlab.actions.merge")
local summary = require("gitlab.actions.summary")
local data = require("gitlab.actions.data")
local assignees_and_reviewers = require("gitlab.actions.assignees_and_reviewers")
local comment = require("gitlab.actions.comment")
local pipeline = require("gitlab.actions.pipeline")
local create_mr = require("gitlab.actions.create_mr")
local approvals = require("gitlab.actions.approvals")
local draft_notes = require("gitlab.actions.draft_notes")
local labels = require("gitlab.actions.labels")
local health = require("gitlab.health")

local user = state.dependencies.user
local info = state.dependencies.info
local labels_dep = state.dependencies.labels
local project_members = state.dependencies.project_members
local latest_pipeline = state.dependencies.latest_pipeline
local revisions = state.dependencies.revisions
local merge_requests_dep = state.dependencies.merge_requests
local merge_requests_by_username_dep = state.dependencies.merge_requests_by_username
local draft_notes_dep = state.dependencies.draft_notes
local discussion_data = state.dependencies.discussion_data

---@param args Settings | {} | nil
---@return nil
local function setup(args)
  if args == nil then
    args = {}
  end
  server.build() -- Builds the Go binary if it doesn't exist
  state.merge_settings(args) -- Merges user settings with default settings
  state.set_global_keymaps() -- Sets keymaps that are not bound to a specific buffer
  require("gitlab.colors") -- Sets colors
  reviewer.init()
  discussions.initialize_discussions() -- place signs / diagnostics for discussions in reviewer
  emoji.init() -- Read in emojis for lookup purposes

  local is_healthy = health.check(true)
  if not is_healthy then
    u.notify("Plugin unhealthy, please run ':checkhealth gitlab' for details", vim.log.levels.WARN)
  end
end

return {
  setup = setup,
  summary = async.sequence({
    u.merge(info, { refresh = true }),
    labels_dep,
  }, summary.summary),
  approve = async.sequence({ info }, approvals.approve),
  revoke = async.sequence({ info }, approvals.revoke),
  add_reviewer = async.sequence({ info, project_members }, assignees_and_reviewers.add_reviewer),
  delete_reviewer = async.sequence({ info, project_members }, assignees_and_reviewers.delete_reviewer),
  add_label = async.sequence({ info, labels_dep }, labels.add_label),
  delete_label = async.sequence({ info, labels_dep }, labels.delete_label),
  add_assignee = async.sequence({ info, project_members }, assignees_and_reviewers.add_assignee),
  delete_assignee = async.sequence({ info, project_members }, assignees_and_reviewers.delete_assignee),
  create_comment = async.sequence({ info, revisions }, comment.create_comment),
  create_multiline_comment = async.sequence({ info, revisions }, comment.create_multiline_comment),
  create_comment_suggestion = async.sequence({ info, revisions }, comment.create_comment_suggestion),
  move_to_discussion_tree_from_diagnostic = async.sequence({}, discussions.move_to_discussion_tree),
  create_note = async.sequence({ info }, comment.create_note),
  create_mr = async.sequence({}, create_mr.start),
  review = async.sequence({ u.merge(info, { refresh = true }), revisions, user }, function()
    reviewer.open()
  end),
  close_review = function()
    reviewer.close()
  end,
  pipeline = async.sequence({ latest_pipeline }, pipeline.open),
  merge = async.sequence({ u.merge(info, { refresh = true }) }, merge.merge),
  -- Discussion Tree Actions 🌴
  toggle_discussions = function()
    if discussions.split_visible then
      discussions.close()
    else
      async.sequence({
        info,
        user,
        u.merge(draft_notes_dep, { refresh = true }),
        u.merge(discussion_data, { refresh = true }),
      }, discussions.open)()
    end
  end,
  toggle_draft_mode = discussions.toggle_draft_mode,
  toggle_sort_method = discussions.toggle_sort_method,
  publish_all_drafts = draft_notes.publish_all_drafts,
  refresh_data = function()
    -- This also rebuilds the regular views
    draft_notes.rebuild_view(false, true)
  end,
  -- Other functions 🤷
  state = state,
  data = data.data,
  print_settings = state.print_settings,
  choose_merge_request = async.sequence({ merge_requests_dep }, merge_requests.choose_merge_request),
  choose_merge_request_by_username = async.sequence(
    { project_members, merge_requests_by_username_dep },
    merge_requests.choose_merge_request
  ),
  open_in_browser = async.sequence({ info }, function()
    local web_url = u.get_web_url()
    if web_url ~= nil then
      u.open_in_browser(web_url)
    end
  end),
  copy_mr_url = async.sequence({ info }, function()
    local web_url = u.get_web_url()
    if web_url ~= nil then
      vim.fn.setreg("+", web_url)
      u.notify("Copied '" .. web_url .. "' to clipboard", vim.log.levels.INFO)
    end
  end),
}
