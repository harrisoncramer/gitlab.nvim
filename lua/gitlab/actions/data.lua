local u = require("gitlab.utils")
local async = require("gitlab.async")
local state = require("gitlab.state")
local M = {}

local user = state.dependencies.user
local info = state.dependencies.info
local labels = state.dependencies.labels
local project_members = state.dependencies.project_members
local revisions = state.dependencies.revisions

M.data = function(opts, cb)
  if type(opts) ~= "table" or type(cb) ~= "function" then
    u.notify("The data function must be passed an opts table and a callback function", vim.log.levels.ERROR)
    return
  end

  local all_resources = {
    user = user,
    labels = labels,
    project_members = project_members,
    revisions = revisions,
  }

  local api_calls = { info }
  for k, v in pairs(all_resources) do
    if opts.resources[k] then
      table.insert(api_calls, v)
    end
  end

  -- TODO: Build an async "parallel" that fetches the resources
  -- in parallel where possible to speed up this API
  return async.sequence(api_calls, function()
    local data = {}
    for k, v in pairs(all_resources) do
      data[k] = state[v.state]
    end
    cb(data)
  end)({ refresh = opts.refresh })
end

return M
