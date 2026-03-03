local List = require("gitlab.utils.list")

local M = {}

---Runs a system command, captures the output (if it exists) and handles errors
---@param command table
---@return string|nil, string|nil
local run_system = function(command)
  local result = vim.fn.trim(vim.fn.system(command))
  if vim.v.shell_error ~= 0 then
    require("gitlab.utils").notify(result, vim.log.levels.ERROR)
    return nil, result
  end
  return result, nil
end

---Returns all branches for the current repository
---@param args table|nil extra arguments for `git branch`
---@return string|nil, string|nil
M.branches = function(args)
  -- Load here to prevent loop
  local u = require("gitlab.utils")
  return run_system(u.combine({ "git", "branch" }, args or {}))
end

---Returns true if the working tree hasn't got any changes that haven't been committed
---@return boolean, string|nil
M.has_clean_tree = function()
  local changes, err = run_system({ "git", "status", "--short", "--untracked-files=no" })
  return changes == "", err
end

---Returns true if the `file` has got any uncommitted changes
---@param file string File to check for changes
---@return boolean, string|nil
M.has_changes = function(file)
  local changes, err = run_system({ "git", "status", "--short", "--untracked-files=no", "--", file })
  return changes ~= "", err
end

---Gets the base directory of the current project
---@return string|nil, string|nil
M.base_dir = function()
  return run_system({ "git", "rev-parse", "--show-toplevel" })
end

---Switches the current project to the given branch
---@return string|nil, string|nil
M.switch_branch = function(branch)
  return run_system({ "git", "checkout", "-q", branch })
end

---Returns the name of the remote-tracking branch for the current branch or nil if it can't be found
---@return string|nil
M.get_remote_branch = function()
  local remote_branch, err = run_system({ "git", "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}" })
  if err or remote_branch == "" then
    require("gitlab.utils").notify("Could not get remote branch: " .. err, vim.log.levels.ERROR)
    return nil
  end
  return remote_branch
end

---Fetch the remote branch
---@param remote_branch string The name of the repo and branch to fetch (e.g., "origin/some_branch")
---@return boolean fetch_successful False if an error occurred while fetching, true otherwise.
M.fetch_remote_branch = function(remote_branch)
  local remote, branch = string.match(remote_branch, "([^/]+)/(.+)")
  if not remote or not branch then
    require("gitlab.utils").notify("Invalid remote branch format: " .. remote_branch, vim.log.levels.ERROR)
    return false
  end
  local _, fetch_err = run_system({ "git", "fetch", remote, branch })
  if fetch_err ~= nil then
    require("gitlab.utils").notify("Error fetching remote-tracking branch: " .. fetch_err, vim.log.levels.ERROR)
    return false
  end
  return true
end

---Determines whether the tracking branch is ahead of or behind the current branch and returns the
---number of ahead and behind commits or nil values in case of errors.
---@param current_branch string|nil
---@param remote_branch string|nil
---@return integer|nil ahead, integer|nil behind
M.get_ahead_behind = function(current_branch, remote_branch)
  if current_branch == nil or remote_branch == nil then
    return nil, nil
  end
  if not M.fetch_remote_branch(remote_branch) then
    return nil, nil
  end

  local u = require("gitlab.utils")
  local result, err =
    run_system({ "git", "rev-list", "--left-right", "--count", current_branch .. "..." .. remote_branch })
  if err ~= nil or result == nil then
    u.notify("Could not determine if branch is up-to-date: " .. err, vim.log.levels.ERROR)
    return nil, nil
  end

  local ahead, behind = result:match("(%d+)%s+(%d+)")
  if ahead == nil or behind == nil then
    u.notify("Error parsing ahead/behind information", vim.log.levels.ERROR)
    return nil, nil
  end

  return tonumber(ahead), tonumber(behind)
end

---Return the name of the current branch, or nil (detached HEAD or git failure).
---@return string|nil
M.get_current_branch = function()
  local current_branch, err = run_system({ "git", "branch", "--show-current" })
  if err then
    require("gitlab.utils").notify("Could not get current branch: " .. err, vim.log.levels.ERROR)
    return nil
  end
  if current_branch == "" then
    -- detached HEAD: `git branch --show-current` returns empty + exit 0
    return nil
  end
  return current_branch
end

---Return the list of possible merge targets.
---@return table|nil
M.get_all_merge_targets = function()
  local current_branch = M.get_current_branch()
  if current_branch == nil then
    return
  end
  return List.new(M.get_all_remote_branches()):filter(function(branch)
    return branch ~= current_branch
  end)
end

---Return the list of names of all remote-tracking branches or an empty list.
---@return table, string|nil
M.get_all_remote_branches = function()
  local state = require("gitlab.state")
  local all_branches, err = M.branches({ "--remotes" })
  if err ~= nil then
    return {}, err
  end
  if all_branches == nil then
    return {}, "Something went wrong getting branches for this repository"
  end

  local u = require("gitlab.utils")
  local lines = u.lines_into_table(all_branches)
  return List.new(lines)
    :map(function(line)
      -- Trim the remote branch
      return line:match(state.settings.connection_settings.remote .. "/(%S+)")
    end)
    :filter(function(branch)
      -- Don't include the HEAD pointer
      return not branch:match("^HEAD$")
    end)
end

---Return whether something
---@param current_branch string
---@return string|nil, string|nil
M.contains_branch = function(current_branch)
  return run_system({ "git", "branch", "-r", "--contains", current_branch })
end

--- Returns true if `branch` is up-to-date on remote, otherwise false and warns user
---@param ahead integer|nil The number of commits the current branch is ahead of remote
---@param behind integer|nil The number of commits the current branch is behind remote
---@param remote_branch string|nil The remote branch, e.g., origin/feature-branch
---@param log_level number
---@return boolean
M.evaluate_ahead_behind = function(ahead, behind, remote_branch, log_level)
  if ahead == nil or behind == nil then
    return false
  end

  local u = require("gitlab.utils")

  if ahead > 0 and behind == 0 then
    u.notify(string.format("There are local changes that haven't been pushed to %s yet", remote_branch), log_level)
    return false
  end
  if behind > 0 and ahead == 0 then
    u.notify(string.format("There are remote changes on %s that haven't been pulled yet", remote_branch), log_level)
    return false
  end

  if ahead > 0 and behind > 0 then
    u.notify(
      string.format(
        "Your branch and the remote %s have diverged. You need to pull, possibly rebase, and then push.",
        remote_branch
      ),
      log_level
    )
    return false
  end

  return true -- Checks passed, branch is up-to-date
end

--- Returns true if `branch` is up-to-date on remote, otherwise false and notifies user.
--- This is a blocking function. For a non-blocking version use
--- gitlab.git_async.check_current_branch_up_to_date_on_remote.
---@param log_level number The log level with which user will be notified
---@return boolean
M.check_current_branch_up_to_date_on_remote = function(log_level)
  local current_branch = M.get_current_branch()
  local remote_branch = M.get_remote_branch()
  local ahead, behind = M.get_ahead_behind(current_branch, remote_branch)
  require("gitlab.state").ahead_behind = { ahead, behind }
  return M.evaluate_ahead_behind(ahead, behind, remote_branch, log_level)
end

---Warns user if the current MR is in a bad state (closed, has conflicts, merged)
M.check_mr_in_good_condition = function()
  local state = require("gitlab.state")
  local u = require("gitlab.utils")

  if state.INFO.has_conflicts then
    u.notify("This merge request has conflicts!", vim.log.levels.WARN)
  end

  if state.INFO.state == "closed" then
    u.notify(string.format("This MR was closed %s", u.time_since(state.INFO.closed_at)), vim.log.levels.WARN)
  end

  if state.INFO.state == "merged" then
    u.notify(string.format("This MR was merged %s", u.time_since(state.INFO.merged_at)), vim.log.levels.WARN)
  end
end

return M
