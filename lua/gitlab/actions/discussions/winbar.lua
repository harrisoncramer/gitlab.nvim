local List = require("gitlab.utils.list")
local state = require("gitlab.state")

local M = {
  bufnr_map = {
    discussions = nil,
    notes = nil,
    draft_notes = nil,
  },
  current_view_type = state.settings.discussion_tree.default_view,
}

M.set_buffers = function(linked_bufnr, unlinked_bufnr, draft_notes_bufnr)
  M.bufnr_map = {
    discussions = linked_bufnr,
    notes = unlinked_bufnr,
    draft_notes = draft_notes_bufnr,
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

  -- TODO: Real data
  local draft_notes = 1

  local t = {
    resolvable_discussions = resolvable_discussions,
    resolved_discussions = resolved_discussions,
    resolvable_notes = resolvable_notes,
    resolved_notes = resolved_notes,
    help_keymap = state.settings.help,
    draft_notes = draft_notes,
  }

  return M.make_winbar(t)
end

--@param view_type string|"discussions"|"notes"

---This function updates the winbar
---@param discussions Discussion[]|nil
---@param unlinked_discussions UnlinkedDiscussion[]|nil
M.update_winbar = function(discussions, unlinked_discussions)
  local d = require("gitlab.actions.discussions")
  local winId = d.split.winid
  local c = content(discussions, unlinked_discussions)
  if vim.wo[winId] then
    vim.wo[winId].winbar = c
  end
end

---@param t WinbarTable
M.make_winbar = function(t)
  local discussions_content = t.resolvable_discussions ~= 0
      and string.format("Discussions (%d/%d)", t.resolved_discussions, t.resolvable_discussions)
    or "Discussions"
  local notes_content = t.resolvable_notes ~= 0 and string.format("Notes (%d/%d)", t.resolved_notes, t.resolvable_notes)
    or "Notes"
  local draft_notes_content = t.draft_notes ~= 0 and string.format("Draft Notes (%d)", t.draft_notes) or "Draft Notes"

  -- Colorize the active tab
  if M.current_view_type == "discussions" then
    discussions_content = "%#Text#" .. discussions_content
    notes_content = "%#Comment#" .. notes_content
    draft_notes_content = "%#Comment#" .. draft_notes_content
  elseif M.current_view_type == "notes" then
    discussions_content = "%#Comment#" .. discussions_content
    notes_content = "%#Text#" .. notes_content
    draft_notes_content = "%#Comment#" .. draft_notes_content
  elseif M.current_view_type == "draft_notes" then
    discussions_content = "%#Comment#" .. discussions_content
    notes_content = "%#Comment#" .. notes_content
    draft_notes_content = "%#Text#" .. draft_notes_content
  end

  -- Join everything together and return it
  local separator = "%#Comment#|"
  local help = "%#Comment#%=Help: " .. t.help_keymap:gsub(" ", "<space>") .. " "
  return string.format(
    " %s %s %s %s %s %s",
    discussions_content,
    separator,
    notes_content,
    separator,
    draft_notes_content,
    help
  )
end

M.switch_view_type = function()
  if M.current_view_type == "discussions" then
    M.current_view_type = "notes"
  elseif M.current_view_type == "notes" then
    M.current_view_type = "draft_notes"
  else
    M.current_view_type = "discussions"
  end

  vim.api.nvim_set_current_buf(M.bufnr_map[M.current_view_type])
  M.update_winbar(M.discussions, M.unlinked_discussions)
end

return M
