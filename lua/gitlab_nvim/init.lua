local Job = require("plenary.job")
local M = {}

M.MERGE_REQUEST_ID = nil

local function error(msg)
  vim.api.nvim_err_writeln("Error: " .. msg)
end

M.comment = function()
  local data = {}
  local current_line_number = vim.api.nvim_call_function('line', { '.' })
  Job:new({
    command = "/Users/harrisoncramer/Desktop/gitlab_nvim/bin",
    args = { "hi", current_line_number, "This is a comment" },
    on_stdout = function(_, line)
      table.insert(data, line)
    end,
    on_exit = function()
      P(data)
    end,
  }):start()
end

M.setup = function(args)
  if args.merge_request_id == nil then
    error("No merge request ID provided")
  end
  M.MERGE_REQUEST_ID = args.merge_request_id
end

return M
