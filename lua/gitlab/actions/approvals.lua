local job = require("gitlab.job")

local M = {}

M.approve = function()
	job.run_job("/mr/approve", "POST")
end

M.revoke = function()
	job.run_job("/mr/revoke", "POST")
end

return M
