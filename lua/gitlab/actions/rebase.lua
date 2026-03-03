-- This module is responsible for rebasing the MR on the Gitlab server and updating the local
-- branch and reviewer state.

local M = {}

---@class RebaseOpts
---@field skip_ci boolean? If true, a CI pipeline is not created.
---@field force boolean? If true, MR is rebased even if MR already is rebased.

---@param opts RebaseOpts
local can_rebase = function(opts)
  local u = require("gitlab.utils")
  -- Check if there are local changes (we wouldn't be able to run `git pull` after rebasing)
  local has_clean_tree, err = require("gitlab.git").has_clean_tree()
  if not has_clean_tree then
    u.notify("Cannot rebase when there are changed files", vim.log.levels.ERROR)
    return false
  elseif err ~= nil then
    u.notify("Error while inspecting working tree", vim.log.levels.ERROR)
    return false
  end

  local state = require("gitlab.state")

  local already_rebased = vim.iter(state.MERGEABILITY):find(function(check)
    return check.identifier == "NEED_REBASE" and check.status == "SUCCESS"
  end)

  local force = require("gitlab.state").settings.rebase_mr.force
  if opts.force ~= nil then
    force = opts.force
  end

  if already_rebased and not force then
    u.notify("MR is already rebased", vim.log.levels.ERROR)
    return false
  end

  local has_conflicts = vim.iter(state.MERGEABILITY):find(function(check)
    return check.identifier == "CONFLICT" and check.status ~= "SUCCESS" and check.status ~= "INACTIVE"
  end)
  if has_conflicts then
    if has_conflicts.status == "FAILED" then
      u.notify("Rebase locally, resolve all conflicts, then push the branch", vim.log.levels.ERROR)
    else
      u.notify("Check for conflicts hasn't passed successfully", vim.log.levels.WARN)
    end
    return false
  end

  return true
end

---Callback to run after the async `git pull` call exits
---@param result string|nil The stdout from the `git pull` call if any.
---@param err string|nil The stderr from the `git pull` call if any.
local on_pull_exit = function(result, err)
  if result ~= nil then
    local reviewer = require("gitlab.reviewer")
    if reviewer.tabid ~= nil then
      reviewer.reload()
    end
  elseif err ~= nil then
    require("gitlab.utils").notify(err, vim.log.levels.ERROR)
  end
end

---@class RebaseBody
---@field skip_ci boolean? If true, a CI pipeline is not created.

---@param rebase_body RebaseBody
local confirm_rebase = function(rebase_body)
  local u = require("gitlab.utils")
  u.notify("Rebase in progress", vim.log.levels.INFO)
  local job = require("gitlab.job")
  job.run_job("/mr/rebase", "POST", rebase_body, function(data)
    u.notify(data.message .. ", updating local state", vim.log.levels.INFO)
    local state = require("gitlab.state")
    require("gitlab.git_async").pull(
      state.settings.connection_settings.remote,
      state.INFO.source_branch,
      on_pull_exit,
      { "--rebase" }
    )
  end)
end

---@param opts RebaseOpts
M.rebase = function(opts)
  opts = opts or {}

  if not can_rebase(opts) then
    return
  end

  local rebase_body = { skip_ci = require("gitlab.state").settings.rebase_mr.skip_ci }
  if opts.skip_ci ~= nil then
    rebase_body.skip_ci = opts.skip_ci
  end

  confirm_rebase(rebase_body)
end

return M
