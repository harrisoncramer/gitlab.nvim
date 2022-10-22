local u     = require("gitlab.utils")
local state = require("gitlab.state")
local Job   = require("plenary.job")
local M     = {}

-- Approves the current merge request
M.approve   = function()
  if u.base_invalid() then return end
  Job:new({
    command = state.BIN,
    args = { "approve", state.PROJECT_ID },
    on_stdout = u.print_success,
    on_stderr = u.print_error
  }):start()
end


return M
