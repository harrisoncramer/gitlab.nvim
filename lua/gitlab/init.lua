local curl         = require("plenary.curl")
local state        = require("gitlab.state")
local discussions  = require("gitlab.discussions")
local summary      = require("gitlab.summary")
local keymaps      = require("gitlab.keymaps")
local comment      = require("gitlab.comment")
local job          = require("gitlab.job")
local u            = require("gitlab.utils")

-- Root Module Scope
local M            = {}
M.summary          = summary.summary
M.approve          = job.approve
M.revoke           = job.revoke
M.create_comment   = comment.create_comment
M.list_discussions = discussions.list_discussions
M.edit_comment     = comment.edit_comment
M.delete_comment   = comment.delete_comment
M.reply            = discussions.reply

-- Builds the Go binary
local function build_binary()
  local command = string.format("cd %s && make", state.BIN_PATH)
  local installCode = os.execute(command .. "> /dev/null")
  if installCode ~= 0 then
    vim.notify("Could not install gitlab.nvim!", vim.log.levels.ERROR)
    return false
  end
  return true
end

M.build = build_binary

-- Setups up the binary (if not built), starts the Go server, and calls the /info endpoint,
-- which sets the Gitlab project's information in gitlab.nvim's state module
M.setup = function(args)
  local file_path = u.current_file_path()
  local parent_dir = vim.fn.fnamemodify(file_path, ":h:h:h:h")
  state.BIN_PATH = parent_dir
  state.BIN = parent_dir .. "/bin"

  if args == nil then
    args = {}
  end

  local binary_exists = vim.loop.fs_stat(state.BIN)
  if binary_exists == nil then
    build_binary()
  end

  local config_file_path = vim.fn.getcwd() .. "/.gitlab.nvim"
  local config_file_content = u.read_file(config_file_path)
  if config_file_content == nil then
    return
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
  if gitlab_url == nil then
    gitlab_url = "https://gitlab.com"
  end

  local auth_token = property["auth_token"]
  if auth_token == nil then
    auth_token = os.getenv("GITLAB_TOKEN")
  end

  if project_id == nil or gitlab_url == nil or auth_token == nil then
    error("Incomplete or invalid configuration file!")
  end

  state.PROJECT_ID = project_id
  state.GITLAB_URL = gitlab_url
  state.AUTH_TOKEN = auth_token

  if state.PROJECT_ID == nil then
    error("No project ID provided!")
  end

  if type(tonumber(state.PROJECT_ID)) ~= "number" then
    error("The .gitlab.nvim project file's 'project_id' must be number")
  end

  if state.AUTH_TOKEN == nil then
    error("No auth token found, in project file or environment")
  end

  if args.base_branch ~= nil then
    state.BASE_BRANCH = args.base_branch
  end

  state.PORT = args.port or 21036

  if u.is_gitlab_repo() then
    local command = state.BIN
        .. " "
        .. state.PROJECT_ID
        .. " "
        .. state.GITLAB_URL
        .. " "
        .. state.PORT
        .. " "
        .. state.AUTH_TOKEN

    vim.fn.jobstart(
      command,
      {
        on_stdout = function(job_id)
          if job_id <= 0 then
            vim.notify("Could not start gitlab.nvim binary", vim.log.levels.ERROR)
            return
          else
            local response_ok, response = pcall(
              curl.get,
              "localhost:" .. state.PORT .. "/info",
              { timeout = 750 }
            )
            if response == nil or not response_ok then
              vim.notify("The gitlab.nvim server did not respond", vim.log.levels.ERROR)
              print("Ran command: " .. command)
              return
            end
            local body = response.body
            local parsed_ok, data = pcall(vim.json.decode, body)
            if parsed_ok ~= true then
              vim.notify("The gitlab.nvim server returned an invalid response to the /info endpoint",
              vim.log.levels.ERROR)
              return
            end
            state.INFO = data
            keymaps.set_keymap_keys(args.keymaps)
            keymaps.set_keymaps()
          end
        end,
      }
    )
  end
end

return M
