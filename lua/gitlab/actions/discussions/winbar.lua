local u = require("gitlab.utils")
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
---@return number, number, number
local get_data = function(nodes)
  local total_resolvable = 0
  local total_resolved = 0
  local total_non_resolvable = 0
  if nodes == nil or nodes == vim.NIL then
    return total_resolvable, total_resolved, total_non_resolvable
  end

  total_resolvable = List.new(nodes):reduce(function(agg, d)
    local first_child = d.notes[1]
    if first_child and first_child.resolvable then
      agg = agg + 1
    end
    return agg
  end, 0)

  total_non_resolvable = List.new(nodes):reduce(function(agg, d)
    local first_child = d.notes[1]
    if first_child and not first_child.resolvable then
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

  return total_resolvable, total_resolved, total_non_resolvable
end

local spinner_index = 0
state.discussion_tree.last_updated = nil

local function content()
  local updated
  if state.discussion_tree.last_updated then
    local last_update = tostring(os.date("!%Y-%m-%dT%H:%M:%S", state.discussion_tree.last_updated))
    updated = u.time_since(last_update) .. " ⟳"
  else
    spinner_index = (spinner_index % #state.settings.discussion_tree.spinner_chars) + 1
    updated = state.settings.discussion_tree.spinner_chars[spinner_index]
  end

  local resolvable_discussions, resolved_discussions, non_resolvable_discussions =
    get_data(state.DISCUSSION_DATA.discussions)
  local resolvable_notes, resolved_notes, non_resolvable_notes = get_data(state.DISCUSSION_DATA.unlinked_discussions)

  local draft_notes = require("gitlab.actions.draft_notes")
  local inline_draft_notes, unlinked_draft_notes = List.new(state.DRAFT_NOTES):partition(function(note)
    if note.discussion_id == "" then
      return draft_notes.has_position(note)
    end
    for _, discussion in ipairs(state.DISCUSSION_DATA.unlinked_discussions) do
      if discussion.id == note.discussion_id then
        return false
      end
    end
    return true
  end)

  local t = {
    resolvable_discussions = resolvable_discussions,
    resolved_discussions = resolved_discussions,
    non_resolvable_discussions = non_resolvable_discussions,
    inline_draft_notes = #inline_draft_notes,
    unlinked_draft_notes = #unlinked_draft_notes,
    resolvable_notes = resolvable_notes,
    resolved_notes = resolved_notes,
    non_resolvable_notes = non_resolvable_notes,
    help_keymap = state.settings.keymaps.help,
    updated = updated,
  }

  return state.settings.discussion_tree.winbar and state.settings.discussion_tree.winbar(t) or M.make_winbar(t)
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

local function get_connector(base_title)
  return string.match(base_title, "%($") and "" or " "
end

---Builds the title string for both sections, using the count of resolvable and draft nodes
---@param base_title string
---@param resolvable_count integer
---@param resolved_count integer
---@param drafts_count integer
---@param focused boolean
---@return string
local add_drafts_and_resolvable = function(
  base_title,
  resolvable_count,
  resolved_count,
  drafts_count,
  non_resolvable_count,
  focused
)
  if resolvable_count == 0 and drafts_count == 0 and non_resolvable_count == 0 then
    return base_title
  end
  if resolvable_count ~= 0 then
    base_title = base_title .. M.get_resolved_text(focused, resolved_count, resolvable_count)
  end
  if non_resolvable_count ~= 0 then
    base_title = base_title .. M.get_nonresolveable_text(base_title, non_resolvable_count, focused)
  end
  if drafts_count ~= 0 then
    base_title = base_title .. M.get_drafts_text(base_title, drafts_count, focused)
  end
  return base_title
end

---@param t WinbarTable
M.make_winbar = function(t)
  local discussions_focused = M.current_view_type == "discussions"
  local discussion_text = add_drafts_and_resolvable(
    "Inline Comments:",
    t.resolvable_discussions,
    t.resolved_discussions,
    t.inline_draft_notes,
    t.non_resolvable_discussions,
    discussions_focused
  )
  local notes_text = add_drafts_and_resolvable(
    "Notes:",
    t.resolvable_notes,
    t.resolved_notes,
    t.unlinked_draft_notes,
    t.non_resolvable_notes,
    not discussions_focused
  )

  -- Colorize the active tab
  if discussions_focused then
    discussion_text = "%#Text#" .. discussion_text
    notes_text = "%#Comment#" .. notes_text
  else
    discussion_text = "%#Comment#" .. discussion_text
    notes_text = "%#Text#" .. notes_text
  end

  local sort_method = M.get_sort_method()
  local mode = M.get_mode()

  -- Join everything together and return it
  local separator = "%#Comment#|"
  local end_section = "%="
  local updated = "%#Text#" .. t.updated
  local help = "%#Comment#Help: " .. (t.help_keymap and t.help_keymap:gsub(" ", "<space>") .. " " or "unmapped")
  return string.format(
    " %s  %s  %s %s %s %s %s %s %s %s %s",
    discussion_text,
    separator,
    notes_text,
    end_section,
    updated,
    separator,
    sort_method,
    separator,
    mode,
    separator,
    help
  )
end

---Returns a string for the winbar indicating the sort method
---@return string
M.get_sort_method = function()
  local sort_method = state.settings.discussion_tree.sort_by == "original_comment" and "↓ by thread" or "↑ by reply"
  return "%#GitlabSortMethod#" .. sort_method .. "%#Comment#"
end

M.get_resolved_text = function(focused, resolved_count, resolvable_count)
  local text = focused and ("%#GitlabResolved#" .. state.settings.discussion_tree.resolved .. "%#Text#")
    or state.settings.discussion_tree.resolved
  return " " .. string.format("%d%s/%d", resolved_count, text, resolvable_count)
end

M.get_drafts_text = function(base_title, drafts_count, focused)
  return get_connector(base_title)
    .. string.format(
      "%d%s",
      drafts_count,
      (
        focused and ("%#GitlabDraft#" .. state.settings.discussion_tree.draft .. "%#Text#")
        or state.settings.discussion_tree.draft
      )
    )
end

M.get_nonresolveable_text = function(base_title, non_resolvable_count, focused)
  return get_connector(base_title)
    .. string.format(
      "%d%s",
      non_resolvable_count,
      (
        focused and ("%#GitlabUnlinked#" .. state.settings.discussion_tree.unlinked .. "%#Text#")
        or state.settings.discussion_tree.unlinked
      )
    )
end

---Returns a string for the winbar indicating the mode type, live or draft
---@return string
M.get_mode = function()
  if state.settings.discussion_tree.draft_mode then
    return "%#GitlabDraftMode#Draft"
  else
    return "%#GitlabLiveMode#Live"
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

-- Set up a timer to update the winbar periodically
local timer = vim.uv.new_timer()
timer:start(0, 100, vim.schedule_wrap(M.update_winbar))

return M
