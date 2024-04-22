local List = require("gitlab.utils.list")

local M = {}

---Runs a system command, captures the output (if it exists) and handles errors
---@param command table
---@return string|nil, string|nil
local run_system = function(command)
  local u = require("gitlab.utils")
  local result = vim.fn.trim(vim.fn.system(command))
  if vim.v.shell_error ~= 0 then
    u.notify(result, vim.log.levels.ERROR)
    return nil, result
  end
  return result, nil
end

---Returns all branches for the current repository
---@return string|nil, string|nil
M.branches = function()
  return run_system({ "git", "branch" })
end

---Checks whether the tree has any changes that haven't been pushed to the remote
---@return string|nil, string|nil
M.has_clean_tree = function()
  return run_system({ "git", "status", "--short", "--untracked-files=no" })
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

---Return the name of the current branch
---@return string|nil, string|nil
M.get_current_branch = function()
  return run_system({ "git", "branch", "--show-current" })
end

---Return the list of possible merge targets.
---@return table|nil
M.get_all_merge_targets = function()
  local current_branch, err = M.get_current_branch()
  if not current_branch or err ~= nil then
    return
  end
  return List.new(M.get_all_remote_branches()):filter(function(branch)
    return branch ~= current_branch
  end)
end

---Return the list of names of all remote-tracking branches or an empty list.
---@return table, string|nil
M.get_all_remote_branches = function()
  local all_branches, err = M.branches()
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
      -- Trim "origin/"
      return line:match("origin/(%S+)")
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

---Returns true if `branch` is up-to-date on remote, false otherwise.
---@param log_level integer
---@return boolean|nil
M.current_branch_up_to_date_on_remote = function(log_level)
  local current_branch = M.get_current_branch()
  local handle = io.popen("git branch -r --contains " .. current_branch .. " 2>&1")
  if not handle then
    require("gitlab.utils").notify("Error running 'git branch' command.", vim.log.levels.ERROR)
    return nil
  end

  local remote_branches_with_current_head = {}
  for line in handle:lines() do
    table.insert(remote_branches_with_current_head, line)
  end
  handle:close()

  local current_head_on_remote = List.new(remote_branches_with_current_head):filter(function(line)
    return line == "  origin/" .. current_branch
  end)
  local remote_up_to_date = #current_head_on_remote == 1

  if not remote_up_to_date then
    require("gitlab.utils").notify(
      "You have local commits that are not on origin. Have you forgotten to push?",
      log_level
    )
  end
  return remote_up_to_date
end

return M
