local async = require("gitlab.async")
local state = require("gitlab.state")
local job = require("gitlab.job")

local info = state.dependencies.info
return {
  shutdown = function()
    if not state.go_server_running then
      vim.notify("The gitlab.nvim server is not running", vim.log.levels.ERROR)
      return
    end

    job.run_job("/shutdown", "DELETE", nil, function()
      state.go_server_running = false
      vim.notify("The gitlab.nvim server was shut down", vim.log.levels.INFO)
    end)
  end,
  restart = function()
    if not state.go_server_running then
      vim.notify("The gitlab.nvim server is not running", vim.log.levels.ERROR)
      return
    end
    job.run_job("/shutdown", "DELETE", nil, function()
      async.sequence({ info }, function()
        state.go_server_running = false
        vim.notify("The gitlab.nvim server was restarted", vim.log.levels.INFO)
      end)
    end)
  end
}
