local notify = require("notify")
local Job    = require("plenary.job")
local M      = {}

M.run_job    = function(endpoint)
  Job:new({
    command = "curl",
    args = { "-s", "-X", "POST", "localhost:8081/" .. endpoint },
    on_stdout = function(_, output)
      local data_ok, data = pcall(vim.json.decode, output)
      if data_ok and data ~= nil then
        local status = (data.status >= 200 and data.status < 300) and "success" or "error"
        notify(data.message, status)
      else
        notify("Could not parse command output!", "error")
      end
    end,
    on_stderr = function(_, output)
      notify("Could not run approve command!", "error")
      error(output)
    end
  }):start()
end

-- Approves the current merge request
M.approve    = function()
  M.run_job("approve")
end

-- Revokes approval for the current merge request
M.revoke     = function()
  M.run_job("revoke")
end

return M
