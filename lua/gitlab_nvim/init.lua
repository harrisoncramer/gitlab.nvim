local Job = require("plenary.job")
local u = require("gitlab_nvim.utils")
local M = {}

M.PROJECT_ID = nil

local function error(msg)
  vim.api.nvim_err_writeln("Error: " .. msg)
end

M.comment = function(comment)
  local data = {}

  local relative_file_path = u.get_relative_file_path()
  local current_line_number = u.get_current_line_number()

  Job:new({
    command = "/Users/harrisoncramer/Desktop/gitlab_nvim/bin",
    args = {
      "comment",
      M.PROJECT_ID,
      current_line_number,
      relative_file_path,
      comment
    },
    on_stdout = function(_, line)
      require("notify")(line, "success")
    end,
    on_stderr = function(_, line)
      require("notify")(line, "error")
    end,
    on_exit = function(code)
    end,
  }):start()
end

M.error = function(msg)
  Job:new({
    command = "/Users/harrisoncramer/Desktop/gitlab_nvim/error.sh",
    on_stderr = function(_, line)
      print("there was an error")
    end,
    on_stdout = function(_, line)
      print(line)
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
      P(data)
    end,
  }):start()
end

M.setup = function(args)
  if args.project_id == nil then
    error("No project ID provided!")
  end
  M.PROJECT_ID = args.project_id
end

return M
