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

  return M.make_winbar(t)
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

---@param t WinbarTable
M.make_winbar = function(t)
  local discussions_content = t.resolvable_discussions ~= 0
      and string.format("Discussions (%d/%d)", t.resolved_discussions, t.resolvable_discussions)
      or "Discussions"
  local notes_content = t.resolvable_notes ~= 0
      and string.format("Notes (%d/%d)", t.resolved_notes, t.resolvable_notes)
      or "Notes"
  if t.name == "Discussions" then
    notes_content = "%#Comment#" .. notes_content
    discussions_content = "%#Text#" .. discussions_content
  else
    discussions_content = "%#Comment#" .. discussions_content
    notes_content = "%#Text#" .. notes_content
  end
  local help = "%#Comment#%=Help: " .. t.help_keymap:gsub(" ", "<space>") .. " "
  return " " .. discussions_content .. " %#Comment#| " .. notes_content .. help
end

return M
