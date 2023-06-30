local notify = require("notify")
local Job    = require("plenary.job")
local state  = require("gitlab.state")
local M      = {}

M.run_job    = function(endpoint, method, body, callback)
  local args = { "-s", "-X", (method or "POST"), string.format("localhost:%s/", state.PORT) .. endpoint }

  if body ~= nil then
    table.insert(args, 1, "-d")
    table.insert(args, 2, body)
  end
  Job:new({
    command = "curl",
    args = args,
    on_stdout = function(_, output)
      local data_ok, data = pcall(vim.json.decode, output)
      if data_ok and data ~= nil then
        local status = (data.status >= 200 and data.status < 300) and "success" or "error"
        if callback ~= nil then
          callback(data)
        else
          notify(data.message, status)
        end
      else
        notify("Could not parse command output!", "error")
      end
    end,
    on_stderr = function(_, output)
      notify("Could not run command!", "error")
      error(output)
    end
  }):start()
end

-- Approves the current merge request
M.approve    = function()
  M.run_job("approve", "POST")
end

-- Revokes approval for the current merge request
M.revoke     = function()
  M.run_job("revoke", "POST")
end


return M
