local job = require("gitlab.job")

local M = {}

M.approve = function()
  job.run_job("/approve", "POST")
end

M.revoke = function()
  job.run_job("/revoke", "POST")
end

return M
