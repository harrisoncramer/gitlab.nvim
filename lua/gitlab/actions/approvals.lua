local client = require("gitlab.client")
local state = require("gitlab.state")
local u = require("gitlab.utils")

local M = {}

---Load mergeability and info data from Gitlab and update the Status window.
local refresh_status_state = function()
  state.load_new_state("mergeability", function()
    state.load_new_state("info", function()
      require("gitlab.actions.summary").update_summary_details()
    end)
  end)
end

---Send the approval to Gitlab, notify user, and re-fresh state.
M.approve = function()
  client.send_request("/mr/approve", "POST", nil, function(data)
    u.notify(data.message, vim.log.levels.INFO)
    refresh_status_state()
  end)
end

---Send the approval revocation to Gitlab, notify user, and re-fresh state.
M.revoke = function()
  client.send_request("/mr/revoke", "POST", nil, function(data)
    u.notify(data.message, vim.log.levels.INFO)
    refresh_status_state()
  end)
end

return M
