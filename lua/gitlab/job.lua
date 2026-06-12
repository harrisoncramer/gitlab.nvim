-- This module is responsible for making API calls to the Go server and
-- running the callbacks associated with those jobs when the JSON is returned
local u = require("gitlab.utils")

local M = {}

---Send a request to the Go server.
---@param endpoint string The endpoint path on the server
---@param method string The HTTP rquest method
---@param callback fun(data: table) The function to run on the decoded JSON response data if the response contains no error details
---@param on_error_callback? fun(data: table) The function to run on the decoded JSON response data in case the response contains error details
M.run_job = function(endpoint, method, body, callback, on_error_callback)
  local state = require("gitlab.state")
  local port = state.settings.server and state.settings.server.port
  local cmd = {
    "curl",
    "--noproxy",
    "localhost",
    "-s",
    "-X",
    (method or "POST"),
    string.format("localhost:%s%s", port, endpoint),
  }

  if body ~= nil then
    local encoded_body = vim.json.encode(body)
    table.insert(cmd, 2, "-d")
    table.insert(cmd, 3, encoded_body)
  end

  -- This handler will handle all responses from the Go server. Anything with a successful
  -- status will call the callback (if it is supplied for the job). Otherwise, it will print out the
  -- success message or error message and details from the Go server and run the on_error_callback
  -- (if supplied for the job).
  vim.system(cmd, { text = true }, function(out)
    vim.schedule(function()
      if out.code ~= 0 then
        u.notify(string.format("Go server exited with non-zero code: %d", out.code), vim.log.levels.ERROR)
      end

      if out.stderr ~= "" then
        u.notify(string.format("Could not run command `%s`! Stderr was:", table.concat(cmd, " ")), vim.log.levels.ERROR)
        u.notify(vim.trim(out.stderr), vim.log.levels.ERROR)
      end

      if out.stdout ~= "" then
        local data_ok, data = pcall(vim.json.decode, out.stdout)
        -- Failing to unmarshal JSON
        if not data_ok then
          local msg = string.format("Failed to parse JSON from %s endpoint", endpoint)
          if type(out.stdout) == "string" then
            msg = string.format(msg .. ", got: '%s'", out.stdout)
          end
          u.notify(string.format(msg, endpoint, out.stdout), vim.log.levels.WARN)
          return
        end

        -- If JSON provided, handle success or error cases
        if data ~= nil then
          if data.details == nil then
            if callback then
              callback(data)
              return
            end
            local message = string.format("%s", data.message)
            u.notify(message, vim.log.levels.INFO)
            return
          end

          -- Handle error case
          local message = string.format("%s: %s", data.message, data.details)
          u.notify(message, vim.log.levels.ERROR)
          if on_error_callback then
            on_error_callback(data)
          end
        end
      end
    end)
  end)
end

return M
