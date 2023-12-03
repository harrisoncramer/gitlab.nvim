local server = require("gitlab.server")
local u = require("gitlab.utils")
local state = require("gitlab.state")
local job = require("gitlab.job")

return {
  shutdown = function()
    if not state.go_server_running then
      vim.notify("The gitlab.nvim server is not running", vim.log.levels.ERROR)
      return
    end
    job.run_job("/shutdown", "POST", { restart = false }, function(data)
      state.go_server_running = false
      state.clear_data()
      u.notify(data.message, vim.log.levels.INFO)
    end)
  end,
  restart = function()
    if not state.go_server_running then
      vim.notify("The gitlab.nvim server is not running", vim.log.levels.ERROR)
      return
    end
    job.run_job("/shutdown", "POST", { restart = true }, function(data)
      state.go_server_running = false
      server.start(function()
        state.go_server_running = true
        state.clear_data()
        u.notify(data.message, vim.log.levels.INFO)
      end)
    end)
  end,
}
