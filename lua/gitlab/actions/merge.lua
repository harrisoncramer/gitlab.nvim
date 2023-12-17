local u = require("gitlab.utils")
local state = require("gitlab.state")
local job = require("gitlab.job")
local reviewer = require("gitlab.reviewer")

local M = {}

---@class MergeOpts
---@field delete_branch boolean?
---@field squash boolean?

---@param opts MergeOpts
M.merge = function(opts)
  local merge_body = { squash = state.settings.merge.squash, delete_branch = state.settings.merge.delete_branch }
  if opts then
    merge_body.squash = opts.squash ~= nil and opts.squash
    merge_body.delete_branch = opts.delete_branch ~= nil and opts.delete_branch
  end

  if state.INFO.detailed_merge_status ~= "mergeable" then
    u.notify(string.format("MR not mergeable, currently '%s'", state.INFO.detailed_merge_status), vim.log.levels.ERROR)
    return
  end

  job.run_job("/merge", "POST", merge_body, function(data)
    reviewer.close()
    u.notify(data.message, vim.log.levels.INFO)
  end)
end

return M
