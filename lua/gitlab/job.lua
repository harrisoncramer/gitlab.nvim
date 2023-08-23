-- This module is responsible for making API calls to the Go server and
-- running the callbacks associated with those jobs when the JSON is returned
local Job = require("plenary.job")
local M   = {}

M.run_job = function(endpoint, method, body, callback)
  local state = require("gitlab.state")
  local args = { "-s", "-X", (method or "POST"), string.format("localhost:%s", state.settings.port) .. endpoint }

  if body ~= nil then
    table.insert(args, 1, "-d")
    table.insert(args, 2, body)
  end

  -- This handler will handle all responses from the Go server. Anything with a successful
  -- status will call the callback (if it is supplied for the job). Otherwise, it will print out the
  -- success message or error message and details from the Go server.
  Job:new({
    command = "curl",
    args = args,
    on_stdout = function(_, output)
      vim.defer_fn(function()
        local data_ok, data = pcall(vim.json.decode, output)
        if not data_ok then
          local msg = string.format("Failed to parse JSON from %s endpoint", endpoint)
          if (type(output) == "string") then msg = string.format(msg .. ", got: '%s'", output) end
          vim.notify(string.format(msg, endpoint, output), vim.log.levels.WARN)
          return
        end
        if data ~= nil then
          local status = (tonumber(data.status) >= 200 and tonumber(data.status) < 300) and "success" or "error"
          if status == "success" and callback ~= nil then
            callback(data)
          elseif status == "success" then
            local message = string.format("%s", data.message)
            vim.notify(message, vim.log.levels.INFO)
          else
            local message = string.format("%s: %s", data.message, data.details)
            vim.notify(message, vim.log.levels.ERROR)
          end
        end
      end, 0)
    end,
    on_stderr = function(_, output)
      vim.defer_fn(function()
        vim.notify("Could not run command!", vim.log.levels.ERROR)
      end, 0)
    end
  }):start()
end

return M
