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

local function content()
  local resolvable_discussions, resolved_discussions = get_data(state.DISCUSSION_DATA.discussions)
  local resolvable_notes, resolved_notes = get_data(state.DISCUSSION_DATA.unlinked_discussions)

  local draft_notes = require("gitlab.actions.draft_notes")
  local inline_draft_notes = List.new(state.DRAFT_NOTES):filter(draft_notes.has_position)
  local unlinked_draft_notes = List.new(state.DRAFT_NOTES):filter(function(note)
    return not draft_notes.has_position(note)
  end)

  local t = {
    resolvable_discussions = resolvable_discussions,
    resolved_discussions = resolved_discussions,
    inline_draft_notes = #inline_draft_notes,
    unlinked_draft_notes = #unlinked_draft_notes,
    resolvable_notes = resolvable_notes,
    resolved_notes = resolved_notes,
    help_keymap = state.settings.help,
  }

  return M.make_winbar(t)
end

---This function updates the winbar
M.update_winbar = function()
  local d = require("gitlab.actions.discussions")
  if d.split == nil then
    return
  end

  local win_id = d.split.winid
  if win_id == nil then
    return
  end

  if not vim.api.nvim_win_is_valid(win_id) then
    return
  end

  local c = content()
  vim.api.nvim_set_option_value("winbar", c, { scope = "local", win = win_id })
end

---Builds the title string for both sections, using the count of resolvable and draft nodes
---@param base_title string
---@param resolvable_count integer
---@param resolved_count integer
---@param drafts_count integer
---@return string
local add_drafts_and_resolvable = function(base_title, resolvable_count, resolved_count, drafts_count)
  if resolvable_count ~= 0 then
    base_title = base_title .. string.format(" (%d/%d resolved", resolvable_count, resolved_count)
  end
  if drafts_count ~= 0 then
    if resolvable_count ~= 0 then
      base_title = base_title .. string.format("; %d drafts)", drafts_count)
    else
      base_title = base_title .. string.format(" (%d drafts)", drafts_count)
    end
  elseif resolvable_count ~= 0 then
    base_title = base_title .. ")"
  end

  return base_title
end

---@param t WinbarTable
M.make_winbar = function(t)
  local discussion_title =
    add_drafts_and_resolvable("Inline Comments", t.resolvable_discussions, t.resolved_discussions, t.inline_draft_notes)
  local notes_title = add_drafts_and_resolvable("Notes", t.resolvable_notes, t.resolved_notes, t.unlinked_draft_notes)

  -- Colorize the active tab
  if M.current_view_type == "discussions" then
    discussion_title = "%#Text#" .. discussion_title
    notes_title = "%#Comment#" .. notes_title
  elseif M.current_view_type == "notes" then
    discussion_title = "%#Comment#" .. discussion_title
    notes_title = "%#Text#" .. notes_title
  end

  local mode = M.get_mode()

  -- Join everything together and return it
  local separator = "%#Comment#|"
  local end_section = "%="
  local help = "%#Comment#Help: " .. t.help_keymap:gsub(" ", "<space>") .. " "
  return string.format(
    " %s %s %s %s %s %s %s",
    discussion_title,
    separator,
    notes_title,
    end_section,
    mode,
    separator,
    help
  )
end

---Returns a string for the winbar indicating the mode type, live or draft
---@return string
M.get_mode = function()
  if state.settings.discussion_tree.draft_mode then
    return "%#DiagnosticWarn#Draft Mode"
  else
    return "%#DiagnosticOK#Live Mode"
  end
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
