local job = require("gitlab.job")
local state = require("gitlab.state")
local u = require("gitlab.utils")

local M = {}

local refresh_status_state = function(data)
  u.notify(data.message, vim.log.levels.INFO)
  state.load_new_state("info", function()
    require("gitlab.actions.summary").update_summary_details()
  end)
end

M.approve = function()
  job.run_job("/mr/approve", "POST", nil, function(data)
    refresh_status_state(data)
  end)
end

M.revoke = function()
  job.run_job("/mr/revoke", "POST", nil, function(data)
    refresh_status_state(data)
  end)
end

return M
