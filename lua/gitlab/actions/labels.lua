-- This module is responsible for the creation, deletion,
-- and assignment and removeal of labels.
local u = require("gitlab.utils")
local job = require("gitlab.job")
local state = require("gitlab.state")
local List = require("gitlab.utils.list")
local M = {}

M.add_label = function()
  M.add_popup("label")
end

M.delete_label = function()
  M.delete_popup("label")
end

local refresh_label_state = function(labels, message)
  u.notify(message, vim.log.levels.INFO)
  state.INFO.labels = labels
  require("gitlab.actions.summary").update_summary_details()
end

local get_current_labels = function()
  return state.INFO.labels
end

local get_all_labels = function()
  return List.new(state.LABELS):map(function(label)
    return label.Name
  end)
end

M.add_popup = function(type)
  local all_labels = get_all_labels()
  local current_labels = get_current_labels()
  local unused_labels = u.difference(all_labels, current_labels)
  vim.ui.select(unused_labels, {
    prompt = "Choose label to add",
  }, function(choice)
    if not choice then
      return
    end
    table.insert(current_labels, choice)
    local body = { labels = current_labels }
    job.run_job("/mr/" .. type, "PUT", body, function(data)
      refresh_label_state(data.labels, data.message)
    end)
  end)
end

M.delete_popup = function(type)
  local current_labels = get_current_labels()
  vim.ui.select(current_labels, {
    prompt = "Choose label to delete",
  }, function(choice)
    if not choice then
      return
    end
    local filtered_labels = u.filter(current_labels, choice)
    local body = { labels = filtered_labels }
    job.run_job("/mr/" .. type, "PUT", body, function(data)
      refresh_label_state(data.labels, data.message)
    end)
  end)
end

return M
