local Job    = require("plenary.job")
local popup  = require("gitlab_nvim.utils.popup")
local u      = require("gitlab_nvim.utils")
local M      = {}

M.PROJECT_ID = nil

-- This function just opens the popup window
M.comment    = function()
  popup:mount()
end

local bin    = "/Users/harrisoncramer/Desktop/gitlab_nvim/bin"

local function printSuccess(_, line)
  if line ~= nil and line ~= "" then
    require("notify")(line, "info")
  end
end

local function printError(_, line)
  if line ~= nil and line ~= "" then
    require("notify")(line, "error")
  end
end

-- This function invokes our binary and sends the text to Gitlab
-- The text comes from the after/ftplugin/gitlab_nvim.lua file
M.sendComment = function(text)
  local relative_file_path = u.get_relative_file_path()
  local current_line_number = u.get_current_line_number()
  Job:new({
    command = bin,
    args = {
      "comment",
      M.PROJECT_ID,
      current_line_number,
      relative_file_path,
      text,
    },
    on_stdout = printSuccess,
    on_stderr = printError
  }):start()
end

M.projectInfo = {}

-- This function fetches some information abour our current repository
-- and sets it in the module
M.initProject = function()
  local data = {}
  Job:new({
    command = bin,
    args = { "projectInfo" },
    on_stdout = function(_, line)
      table.insert(data, line)
    end,
    on_stderr = printError,
    on_exit = function()
      if data[1] ~= nil then
        local parsed = vim.json.decode(data[1])
        M.projectInfo = parsed[1]
      end
    end,
  }):start()
end

M.approve     = function()
  Job:new({
    command = bin,
    args = { "approve" },
    on_stdout = printSuccess,
    on_stderr = printError
  }):start()
end

-- This function initializes the plugin so that we can communicate with Gitlab's API
M.setup       = function(args)
  if args.project_id == nil then
    error("No project ID provided!")
  end
  M.PROJECT_ID = args.project_id

  M.initProject()
end

return M
