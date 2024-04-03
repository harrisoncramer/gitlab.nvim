-- This module is responsible for calling APIs in sequence. It provides
-- an abstraction around the APIs that lets us ensure state.
local server = require("gitlab.server")
local u = require("gitlab.utils")
local job = require("gitlab.job")
local state = require("gitlab.state")

local M = {}

local async = {
  cb = nil,
}

function async:new(o)
  o = o or {}
  setmetatable(o, self)
  self.__index = self
  return o
end

function async:init(cb)
  self.cb = cb
end

function async:fetch(dependencies, i, argTable)
  if i > #dependencies then
    self.cb(argTable)
    return
  end

  local dependency = dependencies[i]

  -- If we have data already and refresh is not required, skip this API call
  if state[dependency.state] ~= nil and not dependency.refresh then
    self:fetch(dependencies, i + 1, argTable)
    return
  end

  -- If the dependency endpoint requires dynamic data, get it and format
  -- it into the endpoint
  local endpoint = dependency.endpoint
  if dependency.args ~= nil then
    for _, f in ipairs(dependency.args) do
      local api_string_arg = f()
      if api_string_arg == nil then
        return
      end
      endpoint = string.format(dependency.endpoint, api_string_arg)
    end
  end

  -- Call the API, set the data, and then call the next API
  job.run_job(endpoint, "GET", dependency.body, function(data)
    state[dependency.state] = data[dependency.key]
    self:fetch(dependencies, i + 1, argTable)
  end)
end

-- Will call APIs in sequence and set global state
M.sequence = function(dependencies, cb)
  return function(argTable)
    local handler = async:new()
    handler:init(cb)

    -- Sets configuration for plugin, if not already set
    if not state.initialized then
      if not state.setPluginConfiguration() then
        return
      end
    end

    -- If go server is already running, then start fetching the values in sequence
    if state.go_server_running then
      handler:fetch(dependencies, 1, argTable)
      return
    end

    -- Otherwise, start the go server and start fetching the values
    server.start(function()
      state.go_server_running = true
      handler:fetch(dependencies, 1, argTable)
    end)
  end
end

return M
