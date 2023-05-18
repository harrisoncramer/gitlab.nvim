local Job           = require("plenary.job")
local state         = require("gitlab.state")
local notify        = require("notify")
local discussions   = require("gitlab.discussions")
local summary       = require("gitlab.summary")
local keymaps       = require("gitlab.keymaps")
local comment       = require("gitlab.comment")
local approve       = require("gitlab.approve")
local revoke        = require("gitlab.revoke")
local u             = require("gitlab.utils")

-- Root Module Scope
local M             = {}
M.summary           = summary.summary
M.approve           = approve.approve
M.revoke            = revoke.revoke
M.create_comment    = comment.create_comment
M.list_discussions  = discussions.list_discussions
M.edit_comment      = comment.edit_comment
M.delete_comment    = comment.delete_comment
M.reply             = discussions.reply

-- Builds the Go binary, initializes the plugin, fetches MR info
local projectData   = {}

local function build_binary(args, notify_on_failure)
  if args == nil then
    args = {}
  end
  local command = string.format("cd %s && make", state.BIN_PATH)
  local installCode = os.execute(command .. "> /dev/null")
  if installCode ~= 0 then
    if notify_on_failure then
      notify("Could not install gitlab.nvim!", "error")
    end
    return false
  end
  return true
end


M.build             = function(args)
  if build_binary(args, true) then
    M.setup(args, true)
  end
end

M.setup             = function(args, build_only)
  local file_path = M.current_file_path()
  local parent_dir = vim.fn.fnamemodify(file_path, ":h:h:h")
  state.BIN_PATH = parent_dir
  state.BIN = parent_dir .. "/bin"

  if args == nil then args = {} end

  local binExists = vim.loop.fs_stat(state.BIN)
    if not build_binary(args, true) then
        return
    end
  end

  local binary_exists = vim.loop.fs_stat(state.BIN)
  if binary_exists == nil then
    return -- Ensure build function completes before initializing plugin
  end

  if build_only then return end

  -- Override project_id in setup call if configuration file is present
  local config_file_path = vim.fn.getcwd() .. "/.gitlab.nvim"
  local config_file_content = u.read_file(config_file_path)
  if config_file_content ~= nil then
    args.project_id = config_file_content
  end

  if args.project_id == nil then
    args.project_id = u.read_file(state.BIN_PATH .. "/.gitlab/project_id")
    if args.project_id == nil then
      error("No project ID provided!")
      return
    end
  end

  state.PROJECT_ID = args.project_id

  if args.base_branch ~= nil then
    state.BASE_BRANCH = args.base_branch
  end

  if u.is_gitlab_repo() then
    Job:new({
      command = state.BIN,
      args = { "info", state.PROJECT_ID },
      on_stdout = function(_, line)
        table.insert(projectData, line)
      end,
      on_stderr = u.print_error,
      on_exit = function()
        if projectData[1] ~= nil then
          local parsed_ok, data = pcall(vim.json.decode, projectData[1])
          if parsed_ok ~= true then
            notify("Failed calling setup. Could not get project data.", "error")
          else
            state.INFO = data
          end
        end
      end,
    }):start()
  end

  keymaps.set_keymap_keys(args.keymaps)
  keymaps.set_keymaps()
end

M.current_file_path = function()
  local path = debug.getinfo(1, 'S').source:sub(2)
  return vim.fn.fnamemodify(path, ':p')
end

return M
