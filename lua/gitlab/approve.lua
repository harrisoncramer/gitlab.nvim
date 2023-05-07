local u      = require("gitlab.utils")
local notify = require("notify")
local Job    = require("plenary.job")
local M      = {}

-- Approves the current merge request
M.approve    = function()
  if u.base_invalid() then return end
  Job:new({
    command = "curl",
    args = { "-s", "-X", "POST", "localhost:8081/approve" },
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


return M
