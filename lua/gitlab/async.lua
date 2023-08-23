local server = require("gitlab.server")
local job    = require("gitlab.job")
local state  = require("gitlab.state")

local M      = {}

Async        = {
  cb = nil
}

function Async:new(o)
  o = o or {}
  setmetatable(o, self)
  self.__index = self
  return o
end

function Async:init(cb)
  self.cb = cb
end

function Async:fetch(ops, i)
  if i > #ops then
    self:cb()
    return
  end

  local dependency = ops[i]

  job.run_job(dependency.endpoint, "GET", dependency.body, function(data)
    state[dependency.state] = data[dependency.key]
    self:fetch(ops, i + 1)
  end)
end

-- Will call APIs in sequence and set global state
M.sequence = function(cb, ops)
  return function()
    local handler = Async:new()
    handler:init(cb)

    if not state.is_gitlab_project then
      vim.notify("The gitlab.nvim state was not set. Do you have a .gitlab.nvim file configured?", vim.log.levels.ERROR)
      return
    end

    if state.go_server_running then
      handler:fetch(ops, 1)
      return
    end

    server.start_server(function()
      state.go_server_running = true
      handler:fetch(ops, 1)
    end)
  end
end

return M
