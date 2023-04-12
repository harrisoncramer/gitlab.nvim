local Job = require("plenary.job")
local M = {}

M.PROJECT_ID = nil

local function error(msg)
  vim.api.nvim_err_writeln("Error: " .. msg)
end

M.comment = function(comment)
  local data = {}
  local current_line_number = vim.api.nvim_call_function('line', { '.' })
  Job:new({
    command = "/Users/harrisoncramer/Desktop/gitlab_nvim/bin",
    args = { M.PROJECT_ID, current_line_number, comment },
    on_stdout = function(_, line)
      table.insert(data, line)
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
