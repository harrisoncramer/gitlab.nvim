local M = {}
local state = require("gitlab.state")

---@param nodes Discussion[]|UnlinkedDiscussion[]|nil
local get_data = function(nodes)
  if nodes == nil then
    return 0, 0
  end
  local total_resolvable = 0
  local total_resolved = 0
  if nodes == vim.NIL then
    return ""
  end

  for _, d in ipairs(nodes) do
    local first_child = d.notes[1]
    if first_child ~= nil then
      if first_child.resolvable then
        total_resolvable = total_resolvable + 1
      end
      if first_child.resolved then
        total_resolved = total_resolved + 1
      end
    end
  end

  return total_resolvable, total_resolved
end

---@param nodes Discussion[]|UnlinkedDiscussion[]|nil
---@param file_name string
local function content(nodes, file_name)
  local resolvable, resolved = get_data(nodes)
  return state.settings.discussion_tree.winbar(file_name, resolvable, resolved)
end

---This function sends the edited comment to the Go server
---@param nodes Discussion[]|UnlinkedDiscussion[]
M.update_winbar = function(nodes, base_title)
  local winId = vim.api.nvim_get_current_win()
  vim.wo[winId].winbar = content(nodes, base_title)
end

return M
