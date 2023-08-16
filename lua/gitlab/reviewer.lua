local u            = require("gitlab.utils")
local job          = require("gitlab.job")
local state        = require("gitlab.state")
local M            = {}

M.assign_reviewer  = function()
  local eligible_assignees = M.filter_reviewers(state.PROJECT_MEMBERS, state.INFO.reviewers)
  vim.ui.select(eligible_assignees, {
    prompt = 'Choose Reviewer',
    format_item = function(user)
      return user.username .. " (" .. user.name .. ")"
    end
  }, function(choice)
    if not choice then return end
    local json = vim.json.encode({ id = choice.id, description = "" })
    job.run_job("mr/reviewer", "PUT", json, function(data)
      vim.notify(data.message, vim.log.levels.INFO)
      state.INFO.reviewers = data.reviewers
    end)
  end)
end

M.remove_reviewer  = function()
end

M.filter_reviewers = function(all_project_members, current_reviewers)
  local reviewer_ids = u.extract(current_reviewers, 'id')
  local res = {}
  for _, member in ipairs(all_project_members) do
    if not u.contains(reviewer_ids, member.id) then table.insert(res, member) end
  end
  return res
end

return M
