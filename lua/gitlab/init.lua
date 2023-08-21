local state                   = require("gitlab.state")
local discussions             = require("gitlab.discussions")
local reviewer                = require("gitlab.reviewer")
local summary                 = require("gitlab.summary")
local assignees_and_reviewers = require("gitlab.assignees_and_reviewers")
local settings                = require("gitlab.settings")
local comment                 = require("gitlab.comment")
local job                     = require("gitlab.job")
local u                       = require("gitlab.utils")

local M                       = {}
M.args                        = nil

-- Builds the binary (if not built) and sets the plugin arguments
M.setup                       = function(args)
  if args == nil then args = {} end

  if not u.has_delta() then
    vim.notify("Please install delta to use gitlab.nvim!", vim.log.levels.ERROR)
    return
  end

  local file_path = u.current_file_path()
  local parent_dir = vim.fn.fnamemodify(file_path, ":h:h:h:h")
  state.settings.bin_path = parent_dir
  state.settings.bin = parent_dir .. "/bin"

  local binary_exists = vim.loop.fs_stat(state.settings.bin)
  if binary_exists == nil then M.build() end

  if not M.setPluginConfiguration(args) then return end -- Return if not a valid gitlab project
  settings.merge_settings(args)                         -- Sets keymaps and other settings or uses fallback from state.lua
  M.args = args                                         -- The  ensureState function won't start without args
end

-- Function names prefixed with "ensure" will ensure the plugin's state
-- is initialized prior to running other calls. These functions run
-- API calls if the state isn't initialized, which will set state containing
-- information that's necessary for other API calls, like description,
-- author, reviewer, etc.
M.ensureState                 = function(callback)
  return function()
    if not M.args then
      vim.notify("The gitlab.nvim state was not set. Do you have a .gitlab.nvim file configured?", vim.log.levels.ERROR)
      return
    end

    if M.go_server_running then
      callback()
      return
    end

    -- Once the Go binary has go_server_running, call the info endpoint to set global state
    M.start_server(function()
      M.go_server_running = true
      job.run_job("info", "GET", nil, function(data)
        state.INFO = data.info
        callback()
      end)
    end)
  end
end

M.print_settings              = function()
  P(state.settings)
end

-- This will start the Go server and call the callback provided
M.go_server_running           = false
M.start_server                = function(callback)
  local command = state.settings.bin
      .. " "
      .. state.settings.project_id
      .. " "
      .. state.settings.gitlab_url
      .. " "
      .. state.settings.port
      .. " "
      .. state.settings.auth_token
      .. " "
      .. state.settings.log_path

  vim.fn.jobstart(command, {
    on_stdout = function(job_id)
      if job_id <= 0 then
        vim.notify("Could not start gitlab.nvim binary", vim.log.levels.ERROR)
      elseif callback ~= nil then
        callback()
      end
    end,
    on_stderr = function(_, errors)
      local err_msg = ''
      for _, err in ipairs(errors) do
        if err ~= "" and err ~= nil then
          err_msg = err_msg .. err .. "\n"
        end
      end
      vim.notify(err_msg, vim.log.levels.ERROR)
    end
  })
end


M.ensureProjectMembers   = function(callback)
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

M.ensureRevisions        = function(callback)
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

-- Builds the Go binary
M.build                  = function()
  if not u.has_delta() then
    vim.notify("Please install delta to use gitlab.nvim!", vim.log.levels.ERROR)
    return
  end
  local command = string.format("cd %s && make", state.settings.bin_path)
  local installCode = os.execute(command .. "> /dev/null")
  if installCode ~= 0 then
    vim.notify("Could not install gitlab.nvim!", vim.log.levels.ERROR)
    return false
  end
  return true
end

-- Initializes state for the project based on the arguments
-- provided in the `.gitlab.nvim` file per project, and the args provided in the setup function
M.setPluginConfiguration = function(args)
  local config_file_path = vim.fn.getcwd() .. "/.gitlab.nvim"
  local config_file_content = u.read_file(config_file_path)
  if config_file_content == nil then
    return false
  end

  local file = assert(io.open(config_file_path, "r"))
  local properties = {}
  for line in file:lines() do
    for key, value in string.gmatch(line, "(.-)=(.-)$") do
      properties[key] = value
    end
  end

  state.settings.project_id = properties.project_id
  state.settings.auth_token = properties.auth_token or os.getenv("GITLAB_TOKEN")
  state.settings.gitlab_url = properties.gitlab_url or "https://gitlab.com"

  if state.settings.auth_token == nil then
    error("Missing authentication token for Gitlab")
  end

  if state.settings.project_id == nil then
    error("Missing project ID in .gitlab.nvim file.")
  end

  if type(tonumber(state.settings.project_id)) ~= "number" then
    error("The .gitlab.nvim project file's 'project_id' must be number")
  end

  return true
end

-- Root Module Scope
-- These functions are exposed when you call require("gitlab").some_function() from Neovim
-- and are bound to settings provided in the setup function
M.summary                = M.ensureState(summary.summary)
M.approve                = M.ensureState(function() job.run_job("approve", "POST") end)
M.revoke                 = M.ensureState(function() job.run_job("revoke", "POST") end)

M.review                 = M.ensureState(function()
  reviewer.open()
  discussions.list_discussions()
end)

M.create_comment         = M.ensureState(M.ensureRevisions(comment.create_comment))

-- Discussion Tree
-- These functions are operating on the discussion tree
M.edit_comment           = M.ensureState(discussions.edit_comment)
M.delete_comment         = M.ensureState(discussions.delete_comment)
M.toggle_resolved        = M.ensureState(discussions.toggle_resolved)
M.reply                  = M.ensureState(discussions.reply)

-- Reviewers + Assignees
M.add_reviewer           = M.ensureState(M.ensureProjectMembers(assignees_and_reviewers.add_reviewer))
M.delete_reviewer        = M.ensureState(M.ensureProjectMembers(assignees_and_reviewers.delete_reviewer))
M.add_assignee           = M.ensureState(M.ensureProjectMembers(assignees_and_reviewers.add_assignee))
M.delete_assignee        = M.ensureState(M.ensureProjectMembers(assignees_and_reviewers.delete_assignee))
M.state                  = state

return M
