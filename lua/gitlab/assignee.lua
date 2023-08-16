local u            = require("gitlab.utils")
local job          = require("gitlab.job")
local state        = require("gitlab.state")
local M            = {}

M.add_assignee     = function()
  local eligible_assignees = M.filter_assignees(state.PROJECT_MEMBERS, state.INFO.assignees)
  vim.ui.select(eligible_assignees, {
    prompt = 'Choose Assignee To Add',
    format_item = function(user)
      return user.username .. " (" .. user.name .. ")"
    end
  }, function(choice)
    if not choice then return end
    local current_ids = u.extract(state.INFO.assignees, 'id')
    table.insert(current_ids, choice.id)
    local json = vim.json.encode({ ids = current_ids })
    job.run_job("mr/assignee", "PUT", json, function(data)
      vim.notify(data.message, vim.log.levels.INFO)
      state.INFO.assignees = data.assignees
    end)
  end)
end

M.delete_assignee  = function()
  local eligible_removals = state.INFO.assignees
  vim.ui.select(eligible_removals, {
    prompt = 'Choose Assignee To Delete',
    format_item = function(user)
      return user.username .. " (" .. user.name .. ")"
    end
  }, function(choice)
    if not choice then return end
    local assignee_ids = u.extract(M.filter_assignees(state.INFO.assignees, { choice }), 'id')
    local json = vim.json.encode({ ids = assignee_ids })
    job.run_job("mr/assignee", "PUT", json, function(data)
      vim.notify(data.message, vim.log.levels.INFO)
      state.INFO.assignees = data.assignees
    end)
  end)
end

M.filter_assignees = function(assignees, assignees_to_remove)
  local assignee_ids = u.extract(assignees_to_remove, 'id')
  local res = {}
  for _, member in ipairs(assignees) do
    if not u.contains(assignee_ids, member.id) then table.insert(res, member) end
  end
  return res
end

return M
