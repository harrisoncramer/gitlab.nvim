local u            = require("gitlab.utils")
local job          = require("gitlab.job")
local state        = require("gitlab.state")
local M            = {}

M.add_reviewer     = function()
  local eligible_reviewers = M.filter_reviewers(state.PROJECT_MEMBERS, state.INFO.reviewers)
  vim.ui.select(eligible_reviewers, {
    prompt = 'Choose Reviewer To Add',
    format_item = function(user)
      return user.username .. " (" .. user.name .. ")"
    end
  }, function(choice)
    if not choice then return end
    local current_ids = u.extract(state.INFO.reviewers, 'id')
    table.insert(current_ids, choice.id)
    local json = vim.json.encode({ ids = current_ids })
    job.run_job("mr/reviewer", "PUT", json, function(data)
      vim.notify(data.message, vim.log.levels.INFO)
      state.INFO.reviewers = data.reviewers
    end)
  end)
end

M.delete_reviewer  = function()
  local eligible_removals = state.INFO.reviewers
  vim.ui.select(eligible_removals, {
    prompt = 'Choose Reviewer To Delete',
    format_item = function(user)
      return user.username .. " (" .. user.name .. ")"
    end
  }, function(choice)
    if not choice then return end
    local reviewer_ids = u.extract(M.filter_reviewers(state.INFO.reviewers, { choice }), 'id')
    local json = vim.json.encode({ ids = reviewer_ids })
    job.run_job("mr/reviewer", "PUT", json, function(data)
      vim.notify(data.message, vim.log.levels.INFO)
      state.INFO.reviewers = data.reviewers
    end)
  end)
end

M.filter_reviewers = function(reviewers, reviewers_to_remove)
  local reviewer_ids = u.extract(reviewers_to_remove, 'id')
  local res = {}
  for _, member in ipairs(reviewers) do
    if not u.contains(reviewer_ids, member.id) then table.insert(res, member) end
  end
  return res
end

return M
