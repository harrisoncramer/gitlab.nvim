local u = require("gitlab.utils")
local state = require("gitlab.state")
local job = require("gitlab.job")

local M = {}

M.merge = function()
  local merge_body = { squash = state.settings.merge.squash, delete_branch = state.settings.merge.delete_branch }
  if state.INFO.detailed_merge_status ~= "mergeable" then
    u.notify(string.format("MR not mergeable, currently '%s'", state.INFO.detailed_merge_status), vim.log.levels.ERROR)
    return
  end

  job.run_job("/merge", "POST", merge_body)
end

return M
