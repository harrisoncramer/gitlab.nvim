-- This module is responsible for making API calls to the Go server and
-- running the callbacks associated with those jobs when the JSON is returned
local u = require("gitlab.utils")

local M = {}

---Shape of a successful response from the Go server. Endpoints typically embed this
---alongside their own endpoint-specific fields (e.g. `discussions`, `info`), which are
---not modeled here since they vary per endpoint.
---@class SuccessResponse
---@field message string

---Shape of an error response from the Go server (see `handleError` in
---`cmd/app/client.go`).
---@class ErrorResponse
---@field message string
---@field error string

---Function to run on the decoded JSON response data if the response contains no error.
---If OnSuccessCallback is omitted, the response's `message` is just notified.
---@alias OnSuccessCallback fun(data: SuccessResponse)

---Function to run if a request fails: called with the decoded response data if it
---contains an error from the Go server, or without arguments if no usable response
---was received at all (transport failure, empty body, or invalid JSON).
---If OnErrorCallback is omitted, the response's `message` and `error` are just
---notified.
---@alias OnErrorCallback fun(data: ErrorResponse?)

---Send a request to the Go server and run callbacks on the output.
---If `on_success` and `on_error` callbacks are provided, exactly one of them runs for
---every request outcome: a successful response, an application-level error from the Go
---server, a transport-level failure (curl error, empty body, or invalid JSON), or
---`curl` itself failing to spawn.
---@param endpoint string The endpoint path on the server
---@param method string The HTTP request method
---@param body? table The request body, if required by the endpoint
---@param on_success? OnSuccessCallback
---@param on_error? OnErrorCallback
M.send_request = function(endpoint, method, body, on_success, on_error)
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

  -- The body can carry comment or MR text, so it must never reach a user facing
  -- message. Both the spawn failure below and the stderr notice in `_make_on_exit`
  -- report this redacted copy rather than `cmd` itself.
  local display_cmd = cmd
  if body ~= nil then
    display_cmd = vim.deepcopy(cmd)
    display_cmd[3] = "REDACTED"
  end

  local ok, err = pcall(vim.system, cmd, { text = true }, M._make_on_exit(display_cmd, endpoint, on_success, on_error))
  -- Curl didn't spawn successfully
  if not ok then
    u.notify(string.format("Failed to spawn `%s`: %s", table.concat(display_cmd, " "), err), vim.log.levels.ERROR)
    if type(on_error) == "function" then
      on_error()
    end
  end
end

---Return the on_exit function for the vim.system call in M.send_request.
---Exported only so tests can call it directly; not part of the public API.
---@param display_cmd string[] The command, with any request body redacted
---@param endpoint string
---@param on_success? OnSuccessCallback
---@param on_error? OnErrorCallback
---@return fun(out: vim.SystemCompleted)
M._make_on_exit = function(display_cmd, endpoint, on_success, on_error)
  return function(out)
    vim.schedule(function()
      -- Notify curl errors. Only WARN since a curl error doesn't exclude valid stdout.
      if out.code ~= 0 or out.signal ~= 0 then
        -- `signal` is checked too: if curl was killed by a signal rather than exiting
        -- normally, `code` isn't meaningful and can read as 0.
        local reason
        if out.signal ~= 0 then
          reason = string.format("killed by signal %d", out.signal)
        else
          reason = string.format(
            "exited with code %d (see https://www.man7.org/linux/man-pages/man1/curl.1.html#EXIT_CODES)",
            out.code
          )
        end
        u.notify(string.format("curl %s", reason), vim.log.levels.WARN)
      end
      if out.stderr ~= "" then
        -- `-s` suppresses curl's own warnings and errors, so non-empty stderr is coming
        -- from outside curl's normal reporting path (a linked library, the dynamic
        -- linker, etc.) - unusual enough to notify.
        u.notify(
          string.format(
            "curl wrote unexpectedly to stderr while running `%s`: %s",
            table.concat(display_cmd, " "),
            vim.trim(out.stderr)
          ),
          vim.log.levels.WARN
        )
      end

      -- Decode response body
      ---@type (SuccessResponse|ErrorResponse)?
      local data
      if out.stdout ~= "" then
        local data_ok
        data_ok, data = pcall(vim.json.decode, out.stdout)
        -- A body that decodes to anything but a table is as unusable as one that doesn't
        -- decode at all: `null` yields `vim.NIL`, and a bare number or string yields a
        -- Lua number or string, none of which can carry `message`/`error`.
        if not data_ok or type(data) ~= "table" then
          -- We don't notify the whole stdout here, as it could be a multi-KB HTML error
          -- page or a truncated multi-KB JSON blob. If the missing information turns
          -- out to be a problem, we should introduce some lua-side logging facility to
          -- log the full content.
          local msg = string.format("Failed to parse JSON from %s endpoint", endpoint)
          -- On a decode failure `data` is pcall's error message; on a successful decode
          -- of a JSON string it's the payload, which is not a decode error.
          if not data_ok and type(data) == "string" then
            msg = string.format(msg .. ", decode error: '%s'", data)
          end
          data = nil
          u.notify(msg, vim.log.levels.ERROR)
        end
      end

      -- Handle decoded response data
      -- No usable response body (curl failed to reach the server (stdout empty), the
      -- body wasn't valid JSON, or it wasn't a JSON object):
      if data == nil then
        if type(on_error) == "function" then
          on_error()
        end
        return
      end
      -- TODO: data.details is checked to prevent breaking for binary_provided users.
      -- Remove in the future.
      if data.details ~= nil and data.error == nil then
        u.notify("Go server returned outdated response format. Rebuild the Go server.", vim.log.levels.WARN)
        data.error = data.details
      end
      -- Application-level error from the Go server:
      if data.error ~= nil then
        if type(on_error) == "function" then
          on_error(data)
        else
          M.notify_error(data)
        end
        return
      end
      -- Successful response:
      if type(on_success) == "function" then
        on_success(data)
      else
        u.notify(string.format("%s", data.message), vim.log.levels.INFO)
      end
    end)
  end
end

---@param data? ErrorResponse
M.notify_error = function(data)
  if data then
    u.notify(string.format("%s: %s", data.message, data.error), vim.log.levels.ERROR)
  end
end

return M
