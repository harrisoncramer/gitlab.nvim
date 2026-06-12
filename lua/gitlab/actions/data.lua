local u = require("gitlab.utils")
local async = require("gitlab.async")
local state = require("gitlab.state")
local M = {}

local user = state.dependencies.user
local info = state.dependencies.info
local labels = state.dependencies.labels
local mergeability = state.dependencies.mergeability
local project_members = state.dependencies.project_members
local revisions = state.dependencies.revisions
local latest_pipeline = state.dependencies.latest_pipeline
local draft_notes = state.dependencies.draft_notes

---@class GitlabResource
---@field type "info"|"user"|"labels"|"mergeability"|"project_members"|"revisions"|"pipeline"|"draft_notes"
---@field refresh boolean If true, refresh the data by hitting Gitlab's APIs again.

---Load the data about the current MR, and execute callback with the date as an argument.
---@param resources GitlabResource[]
---@param cb fun(data)
---@return nil
M.data = function(resources, cb)
  if type(resources) ~= "table" or type(cb) ~= "function" then
    u.notify("The data function must be passed a resources table and a callback function", vim.log.levels.ERROR)
    return
  end

  local all_resources = {
    info = info,
    user = user,
    labels = labels,
    mergeability = mergeability,
    project_members = project_members,
    revisions = revisions,
    pipeline = latest_pipeline,
    draft_notes = draft_notes,
  }

  local api_calls = {}
  for _, resource in ipairs(resources) do
    local api_call = all_resources[resource.type]
    table.insert(api_calls, u.merge(api_call, { refresh = resource.refresh }))
  end

  -- TODO: Build an async "parallel" that fetches the resources
  -- in parallel where possible to speed up this API
  return async.sequence(api_calls, function()
    local data = {}
    -- FIXME: Shouldn't this really be `for k, v in pairs(api_calls) do`?
    for k, v in pairs(all_resources) do
      data[k] = state[v.state]
    end
    cb(data)
  end)()
end

return M
