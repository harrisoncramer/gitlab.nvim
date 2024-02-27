local M = {}
local state = require("gitlab.state")
local List = require("gitlab.utils.list")

---@param nodes Discussion[]|UnlinkedDiscussion[]|nil
---@return number, number
local get_data = function(nodes)
  local total_resolvable = 0
  local total_resolved = 0
  if nodes == nil or nodes == vim.NIL then
    return total_resolvable, total_resolved
  end

  total_resolvable = List.new(nodes):reduce(function(agg, d)
    local first_child = d.notes[1]
    if first_child and first_child.resolvable then
      agg = agg + 1
    end
    return agg
  end, 0)

  total_resolved = List.new(nodes):reduce(function(agg, d)
    local first_child = d.notes[1]
    if first_child and first_child.resolved then
      agg = agg + 1
    end
    return agg
  end, 0)

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
    help_keymap = state.settings.help,
  }

  return state.settings.discussion_tree.winbar(t)
end

---This function updates the winbar
---@param discussions Discussion[]
---@param unlinked_discussions UnlinkedDiscussion[]
---@param base_title string
M.update_winbar = function(discussions, unlinked_discussions, base_title)
  local d = require("gitlab.actions.discussions")
  local winId = d.split.winid
  local c = content(discussions, unlinked_discussions, base_title)
  if vim.wo[winId] then
    vim.wo[winId].winbar = c
  end
end

return M
