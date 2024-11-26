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

local function content()
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

local function get_connector(base_title)
  return string.match(base_title, "%($") and "" or "; "
end

---Builds the title string for both sections, using the count of resolvable and draft nodes
---@param base_title string
---@param resolvable_count integer
---@param resolved_count integer
---@param drafts_count integer
---@return string
local add_drafts_and_resolvable = function(
  base_title,
  resolvable_count,
  resolved_count,
  drafts_count,
  non_resolvable_count
)
  if resolvable_count == 0 and drafts_count == 0 and non_resolvable_count == 0 then
    return base_title
  end
  base_title = base_title .. " ("
  if non_resolvable_count ~= 0 then
    base_title = base_title .. u.pluralize(non_resolvable_count, "comment")
  end
  if resolvable_count ~= 0 then
    base_title = base_title
      .. get_connector(base_title)
      .. string.format("%d/%s", resolved_count, u.pluralize(resolvable_count, "thread"))
  end
  if drafts_count ~= 0 then
    base_title = base_title .. get_connector(base_title) .. u.pluralize(drafts_count, "draft")
  end
  base_title = base_title .. ")"
  return base_title
end

-- Returns true if the input string (after removing highlighting and alignment strings) is wider
-- than the discussion split.
---@return boolean
local too_long = function(str)
  local d = require("gitlab.actions.discussions")
  return #str:gsub("%%#[^#]+#", ""):gsub("%%= ", "") > vim.fn.winwidth(d.split.winid)
end

-- Returns the input winbar string shortened to fit into the windo width.
---@return string
local adapt_to_winwidth = function(str)
  if too_long(str) then
    str = str:gsub("Inline ", "")
  end
  if too_long(str) then
    str = str:gsub("by thread", "thread")
    str = str:gsub("by reply", "reply")
  end
  if too_long(str) then
    str = str:gsub(" Mode", "")
  end
  if too_long(str) then
    str = str:gsub("Help", "H")
  end
  if too_long(str) then
    str = str:gsub("just now", "now")
    str = str:gsub("(%d+) minutes?", "%1m")
    str = str:gsub("(%d+) hours?", "%1h")
    str = str:gsub("(%d+) days?", "%1d")
  end
  if too_long(str) then
    str = str:gsub("↓ thread", "↓")
    str = str:gsub("↑ reply", "↑")
  end
  if too_long(str) then
    str = str:gsub("Updated", "U")
  end
  if too_long(str) then
    str = str:gsub("Draft", "D")
    str = str:gsub("Live", "L")
  end
  if too_long(str) then
    str = str:gsub("(%d+) comments?", "%1c")
  end
  if too_long(str) then
    str = str:gsub("(%d+/%d+) threads?", "%1t")
  end
  if too_long(str) then
    str = str:gsub("(%d+) drafts?", "%1d")
  end
  if too_long(str) then
    str = str:gsub("(%d+%a) ago", "%1")
  end
  if too_long(str) then
    str = str:gsub("Comments", "C")
  end
  if too_long(str) then
    str = str:gsub("Notes", "N")
  end
  return str
end

---@param t WinbarTable
M.make_winbar = function(t)
  local discussion_title = add_drafts_and_resolvable(
    "Inline Comments",
    t.resolvable_discussions,
    t.resolved_discussions,
    t.inline_draft_notes,
    t.non_resolvable_discussions
  )
  local notes_title = add_drafts_and_resolvable(
    "Notes",
    t.resolvable_notes,
    t.resolved_notes,
    t.unlinked_draft_notes,
    t.non_resolvable_notes
  )

  -- Colorize the active tab
  if M.current_view_type == "discussions" then
    discussion_title = "%#Text#" .. discussion_title
    notes_title = "%#Comment#" .. notes_title
  elseif M.current_view_type == "notes" then
    discussion_title = "%#Comment#" .. discussion_title
    notes_title = "%#Text#" .. notes_title
  end

  local sort_method = M.get_sort_method()
  local mode = M.get_mode()

  -- Join everything together and return it
  local separator = "%#Comment#|"
  local end_section = "%="
  local help = "%#Comment#Help: " .. (t.help_keymap and t.help_keymap:gsub(" ", "<space>") .. " " or "unmapped")
  local result = string.format(
    " %s %s %s %s %s %s %s %s %s",
    discussion_title,
    separator,
    notes_title,
    end_section,
    sort_method,
    separator,
    mode,
    separator,
    help
  )
  return adapt_to_winwidth(result)
end

---Returns a string for the winbar indicating the sort method
---@return string
M.get_sort_method = function()
  local sort_method = state.settings.discussion_tree.sort_by == "original_comment" and "↓ by thread" or "↑ by reply"
  return "%#GitlabSortMethod#" .. sort_method
end

---Returns a string for the winbar indicating the mode type, live or draft
---@return string
M.get_mode = function()
  if state.settings.discussion_tree.draft_mode then
    return "%#GitlabDraftMode#Draft Mode"
  else
    return "%#GitlabLiveMode#Live Mode"
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
