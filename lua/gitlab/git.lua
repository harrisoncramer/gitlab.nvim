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

return M
