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

---@param discussions Discussion[]|nil
---@param unlinked_discussions UnlinkedDiscussion[]|nil
---@param file_name string
local function content(discussions, unlinked_discussions, file_name)
  local resolvable_discussions, resolved_discussions = get_data(discussions)
  local resolvable_notes, resolved_notes = get_data(unlinked_discussions)

  local t = {
    name = file_name,
    resolvable_discussions = resolvable_discussions,
    resolved_discussions = resolved_discussions,
    resolvable_notes = resolvable_notes,
    resolved_notes = resolved_notes,
  }

  return state.settings.discussion_tree.winbar(t)
end

---This function sends the edited comment to the Go server
---@param discussions Discussion[]
---@param unlinked_discussions UnlinkedDiscussion[]
---@param base_title string
M.update_winbar = function(discussions, unlinked_discussions, base_title)
  local d = require("gitlab.actions.discussions")
  local winId = d.split.winid
  local c = content(discussions, unlinked_discussions, base_title)
  vim.wo[winId].winbar = c
end

return M
