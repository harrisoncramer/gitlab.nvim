local Job     = require("plenary.job")
local Popup   = require("nui.popup")
local u       = require("gitlab_nvim.utils")
local M       = {}

M.PROJECT_ID  = nil

local event   = require("nui.utils.autocmd").event

local popup   = Popup({
  buf_options = {
    filetype = 'gitlab_nvim'
  },
  enter = true,
  focusable = true,
  border = {
    style = "rounded",
    text = {
      top = "Comment",
    },
  },
  position = "50%",
  size = {
    width = "40%",
    height = "60%",
  },
})

M.popup       = popup

M.comment     = function()
  popup:mount()
end

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

M.setup       = function(args)
  if args.project_id == nil then
    error("No project ID provided!")
  end
  M.PROJECT_ID = args.project_id
end

return M
