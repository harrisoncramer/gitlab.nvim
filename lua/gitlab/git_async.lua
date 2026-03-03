local M = {}

---Function to run when an async system call finishes. Receives the command's stdout as result when
---successful, or the command's stderr as err when unsuccessful.
---@alias OnExitCallback fun(result:string|nil, err:string|nil)

---Function to run on the result of getting the ahead and behind in the get_ahead_behind function.
---@alias GetAheadBehindCallback fun(ahead:integer|nil, behind:integer|nil, remote_branch:string|nil)

---Runs a system command asynchronously
---@param command string[]
---@param on_exit OnExitCallback
local run_system_async = function(command, on_exit)
  vim.system(command, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        require("gitlab.utils").notify(result.stderr, vim.log.levels.ERROR)
        on_exit(nil, result.stderr)
      else
        on_exit(vim.fn.trim(result.stdout), nil)
      end
    end)
  end)
end

---Pull a branch asynchronously from a remote and execute callback on exit.
---@param remote string The remote from which to pull.
---@param branch string The branch to pull.
---@param on_exit OnExitCallback The callback to execute when the command finishes.
---@param args? string[] Extra arguments passed to the `git pull` command.
M.pull = function(remote, branch, on_exit, args)
  local current_branch = require("gitlab.git").get_current_branch()
  if not current_branch then
    return
  end
  if current_branch ~= branch then
    on_exit(nil, "Cannot pull. Remote branch is not the same as current branch")
    return
  end
  local cmd = { "git", "pull" }
  vim.list_extend(cmd, args or {})
  vim.list_extend(cmd, { remote, branch })
  run_system_async(cmd, on_exit)
end

---Fetch the remote branch
---@param remote_branch string The name of the repo and branch to fetch (e.g., "origin/some_branch")
---@param on_exit OnExitCallback
M.fetch_remote_branch = function(remote_branch, on_exit)
  local remote, branch = string.match(remote_branch, "([^/]+)/(.+)")
  if not remote or not branch then
    on_exit(nil, "Invalid remote branch format: " .. remote_branch)
    return
  end
  run_system_async({ "git", "fetch", remote, branch }, on_exit)
end

--- Determines the number of commits the current branch is ahead of or behind the remote branch and
--- runs on_exit callback with the values.
---@param current_branch string|nil
---@param remote_branch string|nil
---@param on_exit GetAheadBehindCallback
M.get_ahead_behind = function(current_branch, remote_branch, on_exit)
  if current_branch == nil or remote_branch == nil then
    on_exit(nil, nil, remote_branch)
    return
  end

  ---Callback to run after the async `git fetch` call exits
  ---@param result string|nil The stdout from the `git fetch` call if any.
  ---@param err string|nil The stderr from the `git fetch` call if any.
  local fetch_remote_branch_callback = function(result, err)
    if result ~= nil then
      local u = require("gitlab.utils")
      run_system_async(
        { "git", "rev-list", "--left-right", "--count", current_branch .. "..." .. remote_branch },
        --- The function to run after the async `git rev-list` call exits
        ---@param r string|nil The stdout from the `git rev-list` call if any.
        ---@param e string|nil The stderr from the `git rev-list` call if any.
        function(r, e)
          if e ~= nil or r == nil then
            u.notify("Could not determine if branch is up-to-date: " .. (e or "unknown error"), vim.log.levels.ERROR)
            on_exit(nil, nil, remote_branch)
            return
          end
          local ahead, behind = r:match("(%d+)%s+(%d+)")
          if ahead == nil or behind == nil then
            u.notify("Error parsing ahead/behind information", vim.log.levels.ERROR)
            on_exit(nil, nil, remote_branch)
            return
          end
          on_exit(tonumber(ahead), tonumber(behind), remote_branch)
        end
      )
    elseif err ~= nil then
      require("gitlab.utils").notify("Error fetching remote-tracking branch: " .. err, vim.log.levels.ERROR)
      on_exit(nil, nil, remote_branch)
    end
  end

  M.fetch_remote_branch(remote_branch, fetch_remote_branch_callback)
end

---Callback to run on the result of getting the ahead and behind in the get_ahead_behind function.
---@param ahead integer|nil The number of commits the current branch is ahead of remote
---@param behind integer|nil The number of commits the current branch is behind remote
---@param remote_branch string|nil The remote from which to pull.
local check_up_to_date_callback = function(ahead, behind, remote_branch)
  require("gitlab.state").ahead_behind = { ahead, behind }
  require("gitlab.git").evaluate_ahead_behind(ahead, behind, remote_branch, vim.log.levels.WARN)
end

--- Evaluates if `branch` is up-to-date on remote and warns user.
--- This is a non-blocking function. For a blocking version that can be used to abort further
--- execution if branch is not up-to-date use gitlab.git.check_current_branch_up_to_date_on_remote.
M.check_current_branch_up_to_date_on_remote = function()
  local git = require("gitlab.git")
  local current_branch = git.get_current_branch()
  local remote_branch = git.get_remote_branch()
  M.get_ahead_behind(current_branch, remote_branch, check_up_to_date_callback)
end

return M
