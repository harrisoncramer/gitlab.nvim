local state                = require("gitlab.state")
local discussions          = require("gitlab.discussions")
local summary              = require("gitlab.summary")
local reviewer             = require("gitlab.reviewer")
local keymaps              = require("gitlab.keymaps")
local comment              = require("gitlab.comment")
local job                  = require("gitlab.job")
local u                    = require("gitlab.utils")

-- Function names prefixed with "ensure" will ensure the plugin's state
-- is initialized prior to running other calls. These functions run
-- API calls if the state isn't initialized, which will set state containing
-- information that's necessary for other API calls, like description,
-- author, reviewer, etc.
local ensureState          = function(callback)
  return function()
    if type(state.INFO) ~= "table" then
      job.run_job("info", "GET", nil, function(data)
        state.INFO = data.info
        callback()
      end)
    else
      callback()
    end
  end
end

local ensureProjectMembers = function(callback)
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

-- Root Module Scope
local M                    = {}
M.summary                  = ensureState(summary.summary)
M.approve                  = ensureState(job.approve)
M.revoke                   = ensureState(job.revoke)
M.create_comment           = ensureState(comment.create_comment)
M.list_discussions         = ensureState(discussions.list_discussions)
M.edit_comment             = ensureState(comment.edit_comment)
M.delete_comment           = ensureState(comment.delete_comment)
M.assign_reviewer          = ensureProjectMembers(reviewer.assign_reviewer)
M.remove_reviewer          = ensureProjectMembers(reviewer.remove_reviewer)
M.reply                    = ensureState(discussions.reply)
M.state                    = state

-- Builds the binary (if not built); starts the Go server; sets the keymaps
M.setup                    = function(args)
  if args == nil then args = {} end
  local file_path = u.current_file_path()
  local parent_dir = vim.fn.fnamemodify(file_path, ":h:h:h:h")
  state.BIN_PATH = parent_dir
  state.BIN = parent_dir .. "/bin"

  local binary_exists = vim.loop.fs_stat(state.BIN)
  if binary_exists == nil then M.build() end

  if not M.setPluginConfiguration(args) then return end -- Return if not a valid gitlab project


  local command = state.BIN
      .. " "
      .. state.PROJECT_ID
      .. " "
      .. state.GITLAB_URL
      .. " "
      .. state.PORT
      .. " "
      .. state.AUTH_TOKEN
      .. " "
      .. state.LOG_PATH

  vim.fn.jobstart(command, {
    on_stdout = function(job_id)
      if job_id <= 0 then
        vim.notify("Could not start gitlab.nvim binary", vim.log.levels.ERROR)
        return
      else
        keymaps.set_keymap_keys(args.keymaps)
        keymaps.set_keymaps()
      end
    end,
    on_stderr = function(_, error)
      vim.notify(error[1], vim.log.levels.ERROR)
    end
  })
end

-- Builds the Go binary
M.build                    = function()
  local command = string.format("cd %s && make", state.BIN_PATH)
  local installCode = os.execute(command .. "> /dev/null")
  if installCode ~= 0 then
    vim.notify("Could not install gitlab.nvim!", vim.log.levels.ERROR)
    return false
  end
  return true
end

-- Initializes state for the project based on the arguments
-- provided in the `.gitlab.nvim` file per project, and the args provided in the setup function
M.setPluginConfiguration   = function(args)
  local config_file_path = vim.fn.getcwd() .. "/.gitlab.nvim"
  local config_file_content = u.read_file(config_file_path)
  if config_file_content == nil then
    return false
  end

  local file = assert(io.open(config_file_path, "r"))
  local property = {}
  for line in file:lines() do
    for key, value in string.gmatch(line, "(.-)=(.-)$") do
      property[key] = value
    end
  end

  local project_id = property["project_id"]
  local gitlab_url = property["gitlab_url"]
  local base_branch = property["base_branch"]
  local auth_token = property["auth_token"]

  state.PROJECT_ID = project_id
  state.AUTH_TOKEN = auth_token or os.getenv("GITLAB_TOKEN")
  state.GITLAB_URL = gitlab_url or "https://gitlab.com"
  state.BASE_BRANCH = base_branch or "main"

  local current_branch_raw = io.popen("git rev-parse --abbrev-ref HEAD"):read("*a")
  local current_branch = string.gsub(current_branch_raw, "\n", "")

  if current_branch == state.BASE_BRANCH then
    return false
  end

  if state.AUTH_TOKEN == nil then
    error("Missing authentication token for Gitlab")
  end

  if state.AUTH_TOKEN == nil then
    error("Missing authentication token for Gitlab")
  end

  if state.PROJECT_ID == nil then
    error("Missing project ID in .gitlab.nvim file.")
  end

  if type(tonumber(state.PROJECT_ID)) ~= "number" then
    error("The .gitlab.nvim project file's 'project_id' must be number")
  end

  -- Configuration for the plugin, such as port of server, layout, etc
  state.PORT = args.port or 21036
  state.LOG_PATH = args.log_path or (vim.fn.stdpath("cache") .. "/gitlab.nvim.log")
  state.DISCUSSION_SPLIT = {
    relative = args.keymaps and args.keymaps.discussion_tree and args.keymaps.discussion_tree.relative or "editor",
    position = args.keymaps and args.keymaps.discussion_tree and args.keymaps.discussion_tree.position or "left",
    size = args.keymaps and args.keymaps.discussion_tree and args.keymaps.discussion_tree.size or "20%",
  }

  return true
end

return M
