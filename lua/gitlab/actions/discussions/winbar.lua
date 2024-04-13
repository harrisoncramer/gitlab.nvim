local List = require("gitlab.utils.list")
local state = require("gitlab.state")

local M = {
  bufnr_map = {
    discussions = nil,
    notes = nil,
  },
  current_view_type = state.settings.discussion_tree.default_view,
}

M.set_buffers = function(linked_bufnr, unlinked_bufnr)
  M.bufnr_map = {
    discussions = linked_bufnr,
    notes = unlinked_bufnr,
  }
end

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

--@param view_type string|"discussions"|"notes"

---@param discussions Discussion[]|nil
---@param unlinked_discussions UnlinkedDiscussion[]|nil
local function content(discussions, unlinked_discussions)
  local resolvable_discussions, resolved_discussions = get_data(discussions)
  local resolvable_notes, resolved_notes = get_data(unlinked_discussions)

  local t = {
    resolvable_discussions = resolvable_discussions,
    resolved_discussions = resolved_discussions,
    resolvable_notes = resolvable_notes,
    resolved_notes = resolved_notes,
    help_keymap = state.settings.help,
  }

  return M.make_winbar(t)
end

---This function updates the winbar
M.update_winbar = function()
  local d = require("gitlab.actions.discussions")
  local winId = d.split.winid
  local c = content(state.DISCUSSION_DATA.discussions, state.DISCUSSION_DATA.unlinked_discussions)
  if vim.wo[winId] then
    vim.wo[winId].winbar = c
  end
end

---@param t WinbarTable
M.make_winbar = function(t)
  local discussions_content = t.resolvable_discussions ~= 0
      and string.format("Inline Comments (%d/%d)", t.resolved_discussions, t.resolvable_discussions)
    or "Inline Comments"
  local notes_content = t.resolvable_notes ~= 0 and string.format("Notes (%d/%d)", t.resolved_notes, t.resolvable_notes)
    or "Notes"

  -- Colorize the active tab
  if M.current_view_type == "discussions" then
    discussions_content = "%#Text#" .. discussions_content
    notes_content = "%#Comment#" .. notes_content
  elseif M.current_view_type == "notes" then
    discussions_content = "%#Comment#" .. discussions_content
    notes_content = "%#Text#" .. notes_content
  end

  -- Join everything together and return it
  local separator = "%#Comment#|"
  local help = "%#Comment#%=Help: " .. t.help_keymap:gsub(" ", "<space>") .. " "
  return string.format(" %s %s %s %s", discussions_content, separator, notes_content, help)
end

---Sets the current view type (if provided an argument)
---and then updates the view
---@param override any
M.switch_view_type = function(override)
  if override then
    M.current_view_type = override
  else
    if M.current_view_type == "discussions" then
      M.current_view_type = "notes"
    elseif M.current_view_type == "notes" then
      M.current_view_type = "discussions"
    end
  end

  vim.api.nvim_set_current_buf(M.bufnr_map[M.current_view_type])
  M.update_winbar()
end

return M
