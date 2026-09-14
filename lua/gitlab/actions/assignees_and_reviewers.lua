-- This module is responsible for the assignment of reviewers
-- and assignees in Gitlab, those who must review an MR.

local u = require("gitlab.utils")
local client = require("gitlab.client")
local List = require("gitlab.utils.list")
local state = require("gitlab.state")
local M = {}

M.add_assignee = function()
  M.add_popup("assignee")
end

M.delete_assignee = function()
  M.delete_popup("assignee")
end

M.add_reviewer = function()
  M.add_popup("reviewer")
end

M.delete_reviewer = function()
  M.delete_popup("reviewer")
end

---Refresh the assignees and reviewers state with new data.
---@param type "assignee"|"reviewer" The type of data to refresh
---@param data table
---@param message string Message from the Go server
local refresh_user_state = function(type, data, message)
  u.notify(message, vim.log.levels.INFO)
  state.INFO[type] = data
  require("gitlab.actions.summary").update_summary_details()
end

---Prompt the user to select a new assignee/reviewer to add to the MR.
---@param type "assignee"|"reviewer" The type of data to add to the MR
M.add_popup = function(type)
  local plural = type .. "s"
  local current = state.INFO[plural]
  local eligible = M.filter_eligible(state.PROJECT_MEMBERS, current)
  vim.ui.select(eligible, {
    prompt = "Choose " .. type .. " to add",
    format_item = function(user)
      return user.username .. " (" .. user.name .. ")"
    end,
  }, function(choice)
    if not choice then
      return
    end
    local current_ids = u.extract(current, "id")
    table.insert(current_ids, choice.id)
    local body = { ids = current_ids }
    client.send_request("/mr/" .. type, "PUT", body, function(data)
      refresh_user_state(plural, data[plural], data.message)
    end)
  end)
end

---Prompt the user to select an existing assignee/reviewer to remove from the MR.
---@param type "assignee"|"reviewer" The type of data to delete from the MR
M.delete_popup = function(type)
  local plural = type .. "s"
  local current = state.INFO[plural]
  vim.ui.select(current, {
    prompt = "Choose " .. type .. " to delete",
    format_item = function(user)
      return user.username .. " (" .. user.name .. ")"
    end,
  }, function(choice)
    if not choice then
      return
    end
    local ids = u.extract(M.filter_eligible(current, { choice }), "id")
    local body = { ids = ids }
    client.send_request("/mr/" .. type, "PUT", body, function(data)
      u.notify(data.message, vim.log.levels.INFO)
      refresh_user_state(plural, data[plural], data.message)
    end)
  end)
end

---@class HasId
---@field id integer The ID of the item

---Return a copy of `current` list of items without items in the `to_remove` list.
---@generic T: HasId
---@generic U: HasId
---@param current T[] Original list of items
---@param to_remove U[] List of items to remove
---@return T[]
M.filter_eligible = function(current, to_remove)
  local ids = u.extract(to_remove, "id")
  return List.new(current):filter(function(member)
    if not u.contains(ids, member.id) then
      return true
    end
  end)
end

return M
