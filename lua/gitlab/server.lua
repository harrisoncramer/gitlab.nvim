-- This module contains the logic responsible for building and starting
-- the Golang server. The Go server is responsible for making API calls
-- to Gitlab and returning the data
local List = require("gitlab.utils.list")
local state = require("gitlab.state")
local u = require("gitlab.utils")
local job = require("gitlab.job")
local Job = require("plenary.job")
local M = {}

-- Builds the binary if it doesn't exist, and starts the server. If the pre-existing binary has an older
-- tag than the Lua code (exposed via the /version endpoint) then shuts down the server, rebuilds it, and
-- restarts the server again.
M.build_and_start = function(callback)
  M.build(false)
  M.start(function()
    M.get_version(function(version)
      if version.plugin_version ~= version.binary_version then
        M.shutdown(function()
          if M.build(true) then
            M.start(callback)
          end
        end)
      else
        callback()
      end
    end)
  end)
end

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
    chosen_mr_iid = state.chosen_mr_iid,
  }

  state.chosen_mr_iid = 0 -- Do not let this interfere with subsequent reviewer.open() calls

  local settings = vim.json.encode(go_server_settings)
  if vim.fn.has("win32") then
    settings = settings:gsub('"', '\\"')
  end

  local command = string.format('"%s" "%s"', state.settings.bin, settings)

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
        state.go_server_running = true
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

-- Builds the Go binary with the current Git tag.
M.build = function(override)
  local file_path = u.current_file_path()
  local parent_dir = vim.fn.fnamemodify(file_path, ":h:h:h:h")

  local bin_name = u.is_windows() and "bin.exe" or "bin"
  state.settings.root_path = parent_dir
  state.settings.bin = parent_dir .. u.path_separator .. "cmd" .. u.path_separator .. bin_name

  if not override then
    local binary_exists = vim.loop.fs_stat(state.settings.bin)
    if binary_exists ~= nil then
      return
    end
  end

  local version_output = vim.system({ "git", "describe", "--tags", "--always" }, { cwd = parent_dir }):wait()
  local version = version_output.code == 0 and vim.trim(version_output.stdout) or "unknown"

  local ldflags = string.format("-X main.Version=%s", version)
  local res = vim
    .system(
      { "go", "build", "-ldflags", ldflags, "-o", bin_name },
      { cwd = state.settings.root_path .. u.path_separator .. "cmd" }
    )
    :wait()

  if res.code ~= 0 then
    u.notify(string.format("Failed to install with status code %d:\n%s", res.code, res.stderr), vim.log.levels.ERROR)
    return false
  end
  u.notify("Installed successfully!", vim.log.levels.INFO)
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
      state.clear_data()
      if cb then
        cb()
      else
        u.notify(data.message, vim.log.levels.INFO)
      end
    end)
  end)
end

-- Returns the version (git tag) that was baked into the binary when it was last built
M.get_version = function(callback)
  if not state.go_server_running then
    u.notify("Gitlab server not running", vim.log.levels.ERROR)
    return nil
  end
  local file_path = u.current_file_path()
  local parent_dir = vim.fn.fnamemodify(file_path, ":h:h:h:h")

  local version_output = vim.system({ "git", "describe", "--tags", "--always" }, { cwd = parent_dir }):wait()
  local plugin_version = version_output.code == 0 and vim.trim(version_output.stdout) or "unknown"

  local args = { "-s", "-X", "GET", string.format("localhost:%s/version", state.settings.port) }

  -- We call the "/version" endpoint here instead of through the regular jobs pattern because earlier versions of the plugin
  -- may not have it. We handle a 404 as an "unknown" version error.
  Job:new({
    command = "curl",
    args = args,
    on_stdout = function(_, output)
      vim.defer_fn(function()
        if output == nil then
          callback({ plugin_version = plugin_version, binary_version = "unknown" })
          return
        end

        local data_ok, data = pcall(vim.json.decode, output)
        if not data_ok or data == nil or data.version == nil then
          callback({ plugin_version = plugin_version, binary_version = "unknown" })
          return
        end

        callback({ plugin_version = plugin_version, binary_version = data.version })
      end, 0)
    end,
    on_stderr = function() end,
    on_exit = function() end,
  }):start()
end

return M
