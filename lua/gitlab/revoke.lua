local u     = require("gitlab.utils")
local state = require("gitlab.state")
local M     = {}
local Job   = require("plenary.job")

-- Revokes approval for the current merge request
M.revoke    = function()
  if u.base_invalid() then return end
  Job:new({
    command = state.BIN,
    args = { "revoke", state.PROJECT_ID },
    on_stdout = u.print_success,
    on_stderr = u.print_error
  }):start()
end

return M
