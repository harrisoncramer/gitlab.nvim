local u = require("gitlab.utils")
local async = require("gitlab.async")
local state = require("gitlab.state")
local M = {}

local user = state.dependencies.user
local info = state.dependencies.info
local labels = state.dependencies.labels
local project_members = state.dependencies.project_members
local revisions = state.dependencies.revisions
local pipeline = state.dependencies.pipeline

M.data = function(resources, cb)
  if type(resources) ~= "table" or type(cb) ~= "function" then
    u.notify("The data function must be passed a resources table and a callback function", vim.log.levels.ERROR)
    return
  end

  local all_resources = {
    info = info,
    user = user,
    labels = labels,
    project_members = project_members,
    revisions = revisions,
    pipeline = pipeline,
  }

  local api_calls = { info }
  for _, resource in ipairs(resources) do
    local api_call = all_resources[resource.type]
    table.insert(api_calls, u.merge(api_call, { refresh = resource.refresh }))
  end

  -- TODO: Build an async "parallel" that fetches the resources
  -- in parallel where possible to speed up this API
  return async.sequence(api_calls, function()
    local data = {}
    for _, v in ipairs(api_calls) do
      data[v.key] = state[v.state]
    end
    cb(data)
  end)()
end

return M
