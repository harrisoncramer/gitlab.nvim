local List = require("gitlab.utils.list")

local M = {}

---Runs a system command, captures the output (if it exists) and handles errors
---@param command table
---@return string|nil, string|nil
local run_system = function(command)
  -- Preserve trailing newlines when getting contents of file revisions
  local result = vim.fn.join(vim.fn.systemlist(command), "\n")
  if vim.v.shell_error ~= 0 then
    if result ~= "" then
      require("gitlab.utils").notify(result, vim.log.levels.ERROR)
    end
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

---Returns true if the working tree hasn't got any changes that haven't been commited
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
---@return boolean fetch_successfull False if an error occurred while fetching, true otherwise.
M.fetch_remote_branch = function(remote_branch)
  local remote, branch = string.match(remote_branch, "([^/]+)/(.*)")
  local _, fetch_err = run_system({ "git", "fetch", remote, branch })
  if fetch_err ~= nil then
    require("gitlab.utils").notify("Error fetching remote-tracking branch: " .. fetch_err, vim.log.levels.ERROR)
    return false
  end
  return true
end

---Determines whether the tracking branch is ahead of or behind the current branch, and warns the user if so
---@param current_branch string
---@param remote_branch string
---@param log_level number
---@return boolean
M.get_ahead_behind = function(current_branch, remote_branch, log_level)
  if not M.fetch_remote_branch(remote_branch) then
    return false
  end

  local u = require("gitlab.utils")
  local result, err =
    run_system({ "git", "rev-list", "--left-right", "--count", current_branch .. "..." .. remote_branch })
  if err ~= nil or result == nil then
    u.notify("Could not determine if branch is up-to-date: " .. err, vim.log.levels.ERROR)
    return false
  end

  local ahead, behind = result:match("(%d+)%s+(%d+)")
  if ahead == nil or behind == nil then
    u.notify("Error parsing ahead/behind information.", vim.log.levels.ERROR)
    return false
  end

  ahead = tonumber(ahead)
  behind = tonumber(behind)

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

---Return the name of the current branch or nil if it can't be retrieved
---@return string|nil
M.get_current_branch = function()
  local current_branch, err = run_system({ "git", "branch", "--show-current" })
  if err or current_branch == "" then
    require("gitlab.utils").notify("Could not get current branch: " .. err, vim.log.levels.ERROR)
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

---Returns true if `branch` is up-to-date on remote, otherwise false and warns user
---@param log_level integer
---@return boolean
M.check_current_branch_up_to_date_on_remote = function(log_level)
  local current_branch = M.get_current_branch()
  if current_branch == nil then
    return false
  end

  local remote_branch = M.get_remote_branch()
  if remote_branch == nil then
    return false
  end

  return M.get_ahead_behind(current_branch, remote_branch, log_level)
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

---@class GetFileRevisionOpts
---@field revision string The SHA of the revision to get
---@field file_name string The name of the file to get

---Returns the contents of the file in a given revision
---@param args GetFileRevisionOpts extra arguments for `git show`
---@return string|nil, string|nil
M.get_file_revision = function(args)
  if args.revision == nil or args.file_name == nil then
    return
  end
  local object = string.format("%s:%s", args.revision, args.file_name)
  return run_system({ "git", "show", object })
end

---Returns true if the given revision exists, false otherwise
---@param revision string The revision to check
---@return boolean
M.revision_exists = function(revision)
  if revision == nil then
    require("gitlab.utils").notify("Invalid nil revision", vim.log.levels.ERROR)
    return false
  end
  local object = string.format("%s", revision)
  local result = run_system({ "git", "rev-parse", "--verify", "--quiet", "--end-of-options", object })
  return result ~= nil
end

---@class FileDiffersInRevisionsOpts
---@field revision_1 string
---@field revision_2 string
---@field old_file_name string
---@field file_name string

---Returns true if the file differs in two revisions (handles renames)
---@param opts FileDiffersInRevisionsOpts
---@return boolean
M.file_differs_in_revisions = function(opts)
  local result =
    run_system({ "git", "diff", "-M", opts.revision_1, opts.revision_2, "--", opts.old_file_name, opts.file_name })
  return result ~= ""
end

---@class AddOpts
---@field filename string The file to stage

---Returns true if staging succeeds, false otherwise
---@param opts AddOpts
---@return boolean
M.add = function(opts)
  local _, add_err = run_system({ "git", "add", opts.filename })
  if add_err ~= nil then
    require("gitlab.utils").notify("Adding changes failed: " .. add_err, vim.log.levels.ERROR)
    return false
  end
  return true
end

---@class CommitOpts
---@field commit_message string The commit message to include in the commit

---Returns true if the commit succeeds, false otherwise
---@param opts CommitOpts
---@return boolean
M.commit = function(opts)
  local _, commit_err = run_system({ "git", "commit", "-m", opts.commit_message, "-q" })
  if commit_err ~= nil then
    require("gitlab.utils").notify("Committing changes failed: " .. commit_err, vim.log.levels.ERROR)
    return false
  end
  return true
end

---Returns true if there are staged changes
---@return boolean
M.has_staged_changes = function()
  local result = run_system({ "git", "diff", "--staged" })
  return result ~= ""
end

---Returns true if the push succeeds, false otherwise
---@return boolean
M.push = function()
  local remote_branch = M.get_remote_branch()
  if remote_branch == nil then
    return false
  end
  local remote, branch = string.match(remote_branch, "([^/]+)/(.*)")
  local _, push_err = run_system({ "git", "push", remote, branch })
  if push_err ~= nil then
    require("gitlab.utils").notify("Pushing remote-tracking branch failed: " .. push_err, vim.log.levels.ERROR)
    return false
  end
  return true
end

return M
