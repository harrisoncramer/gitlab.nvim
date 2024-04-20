local List = require("gitlab.utils.list")

local M = {}

M.has_clean_tree = function()
  return vim.fn.trim(vim.fn.system({ "git", "status", "--short", "--untracked-files=no" })) == ""
end

M.base_dir = function()
  return vim.fn.trim(vim.fn.system({ "git", "rev-parse", "--show-toplevel" }))
end

M.switch_branch = function(branch)
  return vim.fn.trim(vim.fn.system({ "git", "checkout", "-q", branch }))
end

---Return the name of the current branch
---@return string|nil
M.get_current_branch = function()
  local handle = io.popen("git branch --show-current 2>&1")
  if handle then
    return handle:read()
  else
    require("gitlab.utils").notify("Error running 'git branch' command.", vim.log.levels.ERROR)
  end
end

---Return the list of names of all remote-tracking branches or an empty list.
---@return table
M.get_all_remote_branches = function()
  local all_branches = {}
  local handle = io.popen("git branch -r 2>&1")
  if not handle then
    require("gitlab.utils").notify("Error running 'git branch' command.", vim.log.levels.ERROR)
    return all_branches
  end

  for line in handle:lines() do
    table.insert(all_branches, line)
  end
  handle:close()

  return List.new(all_branches)
    :map(function(line)
      -- Trim "origin/"
      return line:match("origin/(%S+)")
    end)
    :filter(function(branch)
      -- Don't include the HEAD pointer
      return not branch:match("^HEAD$")
    end)
end

---Returns: 1. The name of the current branch.
---         2. A Boolean: true if `branch` is up-to-date on remote, false otherwise.
---@return string, boolean
M.current_branch_up_to_date_on_remote = function()
  local current_branch = M.get_current_branch()
  local handle = io.popen("git branch -r --contains " .. current_branch .. " 2>&1")
  if not handle then
    require("gitlab.utils").notify("Error running 'git branch' command.", vim.log.levels.ERROR)
    return "", false
  end

  local remote_branches_with_current_head = {}
  for line in handle:lines() do
    table.insert(remote_branches_with_current_head, line)
  end
  handle:close()

  local current_head_on_remote = List.new(remote_branches_with_current_head)
    :filter(function(line)
      return line == "  origin/" .. current_branch
    end)
  return current_branch or "", #current_head_on_remote == 1
end

return M
