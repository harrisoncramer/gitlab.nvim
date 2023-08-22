local server                  = require("gitlab.server")
local state                   = require("gitlab.state")
local discussions             = require("gitlab.discussions")
local reviewer                = require("gitlab.reviewer")
local summary                 = require("gitlab.summary")
local assignees_and_reviewers = require("gitlab.assignees_and_reviewers")
local comment                 = require("gitlab.comment")
local job                     = require("gitlab.job")
local u                       = require("gitlab.utils")

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

-- Ensure Functions 🤝
-- These functions are used to set global state for actions, since many of
-- the actions require state from Gitlab to run. This lets us defer starting
-- the Golang server until after an action has been taken
M.ensureState                 = function(callback)
  return function()
    if not state.is_gitlab_project then
      vim.notify("The gitlab.nvim state was not set. Do you have a .gitlab.nvim file configured?", vim.log.levels.ERROR)
      return
    end

    if state.go_server_running then
      callback()
      return
    end

    -- Once the Go binary has go_server_running, call the info endpoint to set global state
    server.start_server(function()
      state.go_server_running = true
      job.run_job("info", "GET", nil, function(data)
        state.INFO = data.info
        callback()
      end)
    end)
  end
end

M.ensureProjectMembers        = function(callback)
  return function()
    if type(state.PROJECT_MEMBERS) ~= "table" then
      job.run_job("members", "GET", nil, function(data)
        state.PROJECT_MEMBERS = data.ProjectMembers
        callback()
      end)
    else
      callback()
    end
  end
end

M.ensureRevisions             = function(callback)
  return function()
    if type(state.MR_REVISIONS) ~= "table" then
      job.run_job("mr/revisions", "GET", nil, function(data)
        state.MR_REVISIONS = data.Revisions
        callback()
      end)
    else
      callback()
    end
  end
end

-- Root Module Scope
-- These functions are exposed when you call require("gitlab").some_function() from Neovim
-- and are bound to settings provided in the setup function
M.summary                     = M.ensureState(summary.summary)
M.approve                     = M.ensureState(function() job.run_job("approve", "POST") end)
M.revoke                      = M.ensureState(function() job.run_job("revoke", "POST") end)

M.review                      = M.ensureState(function()
  reviewer.open()
  discussions.list_discussions()
end)

M.create_comment              = M.ensureState(M.ensureRevisions(comment.create_comment))

-- Discussion Tree
-- These functions are operating on the discussion tree
M.edit_comment                = M.ensureState(discussions.edit_comment)
M.delete_comment              = M.ensureState(discussions.delete_comment)
M.toggle_resolved             = M.ensureState(discussions.toggle_resolved)
M.reply                       = M.ensureState(discussions.reply)

-- Reviewers + Assignees
M.add_reviewer                = M.ensureState(M.ensureProjectMembers(assignees_and_reviewers.add_reviewer))
M.delete_reviewer             = M.ensureState(M.ensureProjectMembers(assignees_and_reviewers.delete_reviewer))
M.add_assignee                = M.ensureState(M.ensureProjectMembers(assignees_and_reviewers.add_assignee))
M.delete_assignee             = M.ensureState(M.ensureProjectMembers(assignees_and_reviewers.delete_assignee))
M.state                       = state

return M
