-- This module contains the logic responsible for building and starting
-- the Golang server. The Go server is responsible for making API calls
-- to Gitlab and returning the data
local state = require("gitlab.state")
local u = require("gitlab.utils")
local job = require("gitlab.job")
local Job = require("plenary.job")
local M = {}

-- Builds the binary if it doesn't exist, and starts the server. If the pre-existing binary has an older
-- tag than the Lua code (exposed via the /version endpoint) then shuts down the server, rebuilds it, and
-- restarts the server again.
M.build_and_start = function(callback)
  if M.build(false) == false then
    return
  end

  -- When the user provides their own binary, skip the version check and rebuild cycle.
  -- The user is responsible for keeping their binary up to date.
  local user_provided_binary = state.settings.server.binary_provided

  M.start(function()
    if user_provided_binary then
      callback()
      return
    end
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
  if state.settings.port ~= nil and state.settings.server.port == nil then
    state.settings.server.port = state.settings.port
    u.notify("The setting `port` has been renamed `server.port`", vim.log.levels.WARN)
  end
  local port = tonumber(state.settings.server.port) or 0
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

  local stderr_buf = ""

  local ok, err = pcall(vim.system, { state.settings.server.binary, settings }, {
    stdout = function(_, data)
      if data == nil or parsed_port ~= nil then
        return
      end
      for line in data:gmatch("[^\r\n]+") do
        local matched = line:match("Server started on port:%s+(%d+)")
        if matched ~= nil then
          parsed_port = matched
          vim.schedule(function()
            state.settings.server.port = matched
            state.go_server_running = true
            if not callback_called then
              callback_called = true
              callback()
            end
          end)
          break
        end
      end
    end,
    stderr = function(_, data)
      if data == nil or data == "" then
        return
      end
      stderr_buf = stderr_buf .. data
    end,
  }, function(out)
    if out.code ~= 0 then
      vim.schedule(function()
        local msg = "Golang gitlab server exited: code: " .. out.code .. ", signal: " .. (out.signal or 0)
        if stderr_buf ~= "" then
          msg = msg .. ", msg: " .. vim.trim(stderr_buf)
        end
        u.notify(msg, vim.log.levels.ERROR)
      end)
    end
  end)

  if not ok then
    u.notify("Could not start gitlab.nvim binary: " .. tostring(err), vim.log.levels.ERROR)
  end
end

-- Builds the Go binary with the current Git tag.
M.build = function(override)
  state.settings.root_path = u.get_root_path()

  -- If the user provided a path to the server, don't build it.
  if state.settings.server.binary_provided then
    local binary_exists = vim.loop.fs_stat(state.settings.server.binary)
    if binary_exists == nil then
      u.notify(
        string.format("The user-provided server path (%s) does not exist.", state.settings.server.binary),
        vim.log.levels.ERROR
      )
      return false
    end
    return
  end

  -- If the user did not provide a path, we build it and place it in either the data path, or the
  -- first writable path we find in the runtime.
  local datapath = vim.fn.stdpath("data")
  local runtimepath = vim.api.nvim_list_runtime_paths()
  table.insert(runtimepath, 1, datapath)

  local bin_name = u.is_windows() and "server.exe" or "server"
  local bin_folder
  for _, path in ipairs(runtimepath) do
    local ok, err = vim.loop.fs_access(path, "w")
    if err == nil and ok ~= nil and ok then
      bin_folder = path .. u.path_separator .. "gitlab.nvim" .. u.path_separator .. "bin"
      if vim.fn.mkdir(bin_folder, "p") == 1 then
        state.settings.server.binary = bin_folder .. u.path_separator .. bin_name
        break
      end
    end
  end

  if state.settings.server.binary == nil then
    u.notify("Could not find a writable folder in the runtime path to save the server to.", vim.log.levels.ERROR)
    return
  end

  if not override then
    local binary_exists = vim.loop.fs_stat(state.settings.server.binary)
    if binary_exists ~= nil then
      return
    end
  end

  local version_output = vim
    .system({ "git", "describe", "--tags", "--always" }, { cwd = state.settings.root_path })
    :wait()
  local version = version_output.code == 0 and vim.trim(version_output.stdout) or "unknown"

  local ldflags = string.format("-X main.Version=%s", version)
  local res = vim
    .system(
      { "go", "build", "-buildvcs=false", "-ldflags", ldflags, "-o", state.settings.server.binary },
      { cwd = state.settings.root_path .. u.path_separator .. "cmd" }
    )
    :wait()

  if res.code ~= 0 then
    u.notify(string.format("Failed to install with status code %d:\n%s", res.code, res.stderr), vim.log.levels.ERROR)
    return false
  end

  local Path = require("plenary.path")
  local src = Path:new(state.settings.root_path .. u.path_separator .. "cmd" .. u.path_separator .. "config")
  local dest = Path:new(bin_folder .. u.path_separator .. "config")
  src:copy({ destination = dest, recursive = true, override = true })

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
  local parent_dir = u.get_root_path()

  local version_output = vim.system({ "git", "describe", "--tags", "--always" }, { cwd = parent_dir }):wait()
  local plugin_version = version_output.code == 0 and vim.trim(version_output.stdout) or "unknown"

  local args =
    { "--noproxy", "localhost", "-s", "-X", "GET", string.format("localhost:%s/version", state.settings.server.port) }

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
