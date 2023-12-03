local async = require("gitlab.async")
local u = require("gitlab.utils")
local state = require("gitlab.state")
local job = require("gitlab.job")

-- local info = state.dependencies.info
return {
  shutdown = function()
    if not state.go_server_running then
      vim.notify("The gitlab.nvim server is not running", vim.log.levels.ERROR)
      return
    end
    job.run_job("/shutdown", "POST", { restart = false }, function(data)
      state.go_server_running = false
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
      u.notify(data.message, vim.log.levels.INFO)
    end)
  end
}
