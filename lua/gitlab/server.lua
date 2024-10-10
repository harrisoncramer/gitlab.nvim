-- This module contains the logic responsible for building and starting
-- the Golang server. The Go server is responsible for making API calls
-- to Gitlab and returning the data
local List = require("gitlab.utils.list")
local state = require("gitlab.state")
local u = require("gitlab.utils")
local job = require("gitlab.job")
local M = {}

-- Starts the Go server and call the callback provided
M.start = function(callback)
  local port = tonumber(state.settings.port) or 0
  local parsed_port = nil
  local callback_called = false

  local go_server_settings = {
    gitlab_url = state.settings.gitlab_url,
    port = port,
    auth_token = state.settings.auth_token,
    debug = state.settings.debug,
    log_path = state.settings.log_path,
    connection_settings = state.settings.connection_settings,
    chosen_target_branch = state.chosen_target_branch,
  }

  state.chosen_target_branch = nil -- Do not let this interfere with subsequent reviewer.open() calls

  local settings = vim.json.encode(go_server_settings)
  local command = string.format("%s '%s'", state.settings.bin, settings)

  local job_id = vim.fn.jobstart(command, {
    on_stdout = function(_, data)
      -- if port was not provided then we need to parse it from output of server
      if parsed_port == nil then
        for _, line in ipairs(data) do
          port = line:match("Server started on port:%s+(%d+)")
          if port ~= nil then
            parsed_port = port
            state.settings.port = port
            break
          end
        end
      end

      -- This assumes that first output of server will be parsable and port will be correctly set.
      -- Make sure that this actually check if port was correctly parsed based on server output
      -- because server outputs port only if it started successfully.
      if parsed_port ~= nil and not callback_called then
        callback()
        callback_called = true
      end
    end,
    on_stderr = function(_, errors)
      local err_msg = List.new(errors):reduce(function(agg, err)
        if err ~= "" and err ~= nil then
          agg = agg .. err .. "\n"
        end
        return agg
      end, "")

      if err_msg ~= "" then
        u.notify(err_msg, vim.log.levels.ERROR)
      end
    end,
    on_exit = function(job_id, exit_code)
      if exit_code ~= 0 then
        u.notify(
          "Golang gitlab server exited: job_id: " .. job_id .. ", exit_code: " .. exit_code,
          vim.log.levels.ERROR
        )
      end
    end,
  })
  if job_id <= 0 then
    u.notify("Could not start gitlab.nvim binary", vim.log.levels.ERROR)
  end
end

-- Builds the Go binary
M.build = function(override)
  local file_path = u.current_file_path()
  local parent_dir = vim.fn.fnamemodify(file_path, ":h:h:h:h")
  state.settings.bin_path = parent_dir
  state.settings.bin = parent_dir .. (u.is_windows() and "\\bin.exe" or "/bin")

  if not override then
    local binary_exists = vim.loop.fs_stat(state.settings.bin)
    if binary_exists ~= nil then
      return
    end
  end

  local cmd = u.is_windows() and "cd %s\\cmd && go build -o bin.exe && move bin.exe ..\\"
    or "cd %s/cmd && go build -o bin && mv bin ../bin"

  local command = string.format(cmd, state.settings.bin_path)
  local null = u.is_windows() and " >NUL" or " > /dev/null"
  local installCode = os.execute(command .. null)
  if installCode ~= 0 then
    u.notify("Could not install gitlab.nvim!", vim.log.levels.ERROR)
    return false
  end
  u.notify("Gitlab.nvim installed successfully!", vim.log.levels.INFO)
  return true
end

-- Shuts down the Go server and clears out all old gitlab.nvim state
M.shutdown = function(cb)
  if not state.go_server_running then
    vim.notify("The gitlab.nvim server is not running", vim.log.levels.ERROR)
    return
  end
  job.run_job("/shutdown", "POST", { restart = false }, function(data)
    state.go_server_running = false
    state.clear_data()
    if cb then
      cb()
    else
      u.notify(data.message, vim.log.levels.INFO)
    end
  end)
end

---Restarts the Go server and clears out all gitlab.nvim state
M.restart = function(cb)
  if not state.go_server_running then
    vim.notify("The gitlab.nvim server is not running", vim.log.levels.ERROR)
    return
  end
  job.run_job("/shutdown", "POST", { restart = true }, function(data)
    state.go_server_running = false
    M.start(function()
      state.go_server_running = true
      state.clear_data()
      if cb then
        cb()
      else
        u.notify(data.message, vim.log.levels.INFO)
      end
    end)
  end)
end

return M
