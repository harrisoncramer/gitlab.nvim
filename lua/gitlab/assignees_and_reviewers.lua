local u           = require("gitlab.utils")
local job         = require("gitlab.job")
local state       = require("gitlab.state")
local M           = {}

M.add_assignee    = function()
  local type = 'assignee'
  M.add_popup(type)
end

M.delete_assignee = function()
  local type = 'assignee'
  M.delete_popup(type)
end

M.add_reviewer    = function()
  local type = 'reviewer'
  M.add_popup(type)
end

M.delete_reviewer = function()
  local type = 'reviewer'
  M.delete_popup(type)
end

M.add_popup       = function(type)
  local plural = type .. 's'
  local current = state.INFO[plural]
  local eligible = M.filter_eligible(state.PROJECT_MEMBERS, current)
  vim.ui.select(eligible, {
    prompt = 'Choose ' .. type .. ' to add',
    format_item = function(user)
      return user.username .. " (" .. user.name .. ")"
    end
  }, function(choice)
    if not choice then return end
    local current_ids = u.extract(current, 'id')
    table.insert(current_ids, choice.id)
    local json = vim.json.encode({ ids = current_ids })
    job.run_job("mr/" .. type, "PUT", json, function(data)
      vim.notify(data.message, vim.log.levels.INFO)
      state.INFO[plural] = data[plural]
    end)
  end)
end

M.delete_popup    = function(type)
  local plural = type .. 's'
  local current = state.INFO[plural]
  vim.ui.select(current, {
    prompt = 'Choose ' .. type .. ' to delete',
    format_item = function(user)
      return user.username .. " (" .. user.name .. ")"
    end
  }, function(choice)
    if not choice then return end
    local ids = u.extract(M.filter_eligible(current, { choice }), 'id')
    local json = vim.json.encode({ ids = ids })
    job.run_job("mr/" .. type, "PUT", json, function(data)
      vim.notify(data.message, vim.log.levels.INFO)
      state.INFO[plural] = data[plural]
    end)
  end)
end

M.filter_eligible = function(current, to_remove)
  local ids = u.extract(to_remove, 'id')
  local res = {}
  for _, member in ipairs(current) do
    if not u.contains(ids, member.id) then table.insert(res, member) end
  end
  return res
end

return M
