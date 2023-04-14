local Job     = require("plenary.job")
local popup   = require("gitlab_nvim.utils.popup")
local u       = require("gitlab_nvim.utils")
local M       = {}

M.PROJECT_ID  = nil

-- This function just opens the popup window
M.comment     = function()
  popup:mount()
end

-- This function invokes our binary and sends the text to Gitlab
-- The text comes from the after/ftplugin/gitlab_nvim.lua file
M.sendComment = function(text)
  local relative_file_path = u.get_relative_file_path()
  local current_line_number = u.get_current_line_number()
  Job:new({
    command = "/Users/harrisoncramer/Desktop/gitlab_nvim/bin",
    args = {
      "comment",
      M.PROJECT_ID,
      current_line_number,
      relative_file_path,
      text,
    },
    on_stdout = function(_, line)
      require("notify")(line, "info")
    end,
    on_stderr = function(_, line)
      require("notify")(line, "error")
    end,
    on_exit = function(code)
    end,
  }):start()
end

-- This function fetches some information abour our current repository
-- and prints it to the screen
M.projectInfo = function()
  local data = {}
  Job:new({
    command = "/Users/harrisoncramer/Desktop/gitlab_nvim/bin",
    args = { "projectInfo" },
    on_stdout = function(_, line)
      table.insert(data, line)
    end,
    on_stderr = function(_, line)
      print(line)
    end,
    on_exit = function()
      u.P(data)
    end,
  }):start()
end

-- This function initializes the plugin so that we can communicate with
-- Gitlab's API
M.setup       = function(args)
  if args.project_id == nil then
    error("No project ID provided!")
  end
  M.PROJECT_ID = args.project_id
end

return M
