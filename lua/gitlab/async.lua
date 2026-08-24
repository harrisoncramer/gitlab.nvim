-- This module is responsible for calling APIs in sequence. It provides
-- an abstraction around the APIs that lets us ensure state.

local server = require("gitlab.server")
local client = require("gitlab.client")
local state = require("gitlab.state")

local M = {}

---@class Async
---@field cb fun(args: table)?
local async = {
  cb = nil,
}

---Create a new Async instance, using `o` as the backing table if provided.
---@param o? table
---@return Async
function async:new(o)
  o = o or {}
  setmetatable(o, self)
  self.__index = self
  return o
end

---Set the callback to invoke once all dependencies have been fetched.
---@param cb fun(args: table)
function async:init(cb)
  self.cb = cb
end

---Make request to the Go server if necessary, set state, and call next dependency.
---If this is the last dependency, execute self.cb with the args as the parameter.
---@param dependencies GitlabDependency[]
---@param i integer The index of the dependency to call in the dependencies table
---@param args table The args to pass to the self.cb function
function async:fetch(dependencies, i, args)
  if i > #dependencies then
    self.cb(args)
    return
  end

  local dependency = dependencies[i]

  -- If we have data already and refresh is not required, skip this API call
  if state[dependency.state] ~= nil and not dependency.refresh then
    self:fetch(dependencies, i + 1, args)
    return
  end

  -- Call the API, set the data, and then call the next API
  -- TODO: Add a on_error callback that will call choose_merge_request for the user:
  -- function(data)
  --   if data.error and data.error:match("call gitlab.choose_merge_request") then
  --     require("gitlab").choose_merge_request(OPTS)
  --   end
  -- end
  -- Find a way to pass the right OPTS.open_reviewer option - don't open the reviewer if
  -- the user just wanted to see the summary, add a reviewer, or similar.
  local body = dependency.body and dependency.body(args) or nil
  client.send_request(dependency.endpoint, dependency.method or "GET", body, function(data)
    state[dependency.state] = dependency.key and data[dependency.key] or data
    -- TODO: Consider if this cannot be called outside of the send_request callback to
    -- fetch the dependencies in parallel rather than in sequence and run self.cb in
    -- this callback instead of self:fetch when the last dependency has been fetched.
    self:fetch(dependencies, i + 1, args)
  end)
end

---Return a function that will start fetching in sequence the dependencies and will
---execute `cb` with the args the function is called with.
---Sets plugin configuration and builds and starts the server if necessary.
---@generic T
---@param dependencies GitlabDependency[]
---@param cb fun(argrs: T)
---@return fun(argrs: T)
M.sequence = function(dependencies, cb)
  return function(args)
    local handler = async:new()
    handler:init(cb)

    -- Sets configuration for plugin, if not already set
    if not state.initialized then
      if not state.set_plugin_configuration() then
        return
      end
    end

    -- If go server is already running, then start fetching the values in sequence
    if state.go_server_running then
      handler:fetch(dependencies, 1, args)
      return
    end

    -- Otherwise, start the go server and start fetching the values
    server.build_and_start(function()
      handler:fetch(dependencies, 1, args)
    end)
  end
end

return M
