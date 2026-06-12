local u = require("gitlab.utils")
local List = require("gitlab.utils.list")
local state = require("gitlab.state")

local M = {}

---Return the number of resolvable, resolved, and non-resolvable comments.
---@param nodes? Discussion[]|UnlinkedDiscussion[]
---@return integer total_resolvable
---@return integer total_resolved
---@return integer total_non_resolvable
local get_data = function(nodes)
  local total_resolvable = 0
  local total_resolved = 0
  local total_non_resolvable = 0
  if nodes == nil or nodes == vim.NIL then
    return total_resolvable, total_resolved, total_non_resolvable
  end

  total_resolvable = List.new(nodes):reduce(function(agg, node)
    local first_child = node.notes[1]
    if first_child and first_child.resolvable then
      agg = agg + 1
    end
    return agg
  end, 0)

  total_non_resolvable = List.new(nodes):reduce(function(agg, node)
    local first_child = node.notes[1]
    if first_child and not first_child.resolvable then
      agg = agg + 1
    end
    return agg
  end, 0)

  total_resolved = List.new(nodes):reduce(function(agg, node)
    local first_child = node.notes[1]
    if first_child and first_child.resolved then
      agg = agg + 1
    end
    return agg
  end, 0)

  return total_resolvable, total_resolved, total_non_resolvable
end

local spinner_index = 0
state.discussion_tree.last_updated = nil

---Return the raw content of the winbar.
---@return string
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
    ahead = state.ahead_behind[1],
    behind = state.ahead_behind[2],
    updated = updated,
  }

  return state.settings.discussion_tree.winbar and state.settings.discussion_tree.winbar(t) or M.make_winbar(t)
end

---Update the winbar.
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

---TODO: remove this function and hardcode " " where called
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
---@return string winbar The raw content of the winbar
M.make_winbar = function(t)
  local discussions_focused = require("gitlab.actions.discussions").current_view_type == "discussions"
  local discussion_text = add_drafts_and_resolvable(
    "Comments:",
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
  local ahead_behind = M.get_ahead_behind(t.ahead, t.behind)
  local help = "%#Comment#Help: " .. (t.help_keymap and t.help_keymap:gsub(" ", "<space>") .. " " or "unmapped")
  return string.format(
    " %s  %s  %s %s %s %s %s %s %s %s %s %s %s",
    discussion_text,
    separator,
    notes_text,
    end_section,
    updated,
    separator,
    ahead_behind,
    separator,
    sort_method,
    separator,
    mode,
    separator,
    help
  )
end

---Return a string for the winbar indicating the sort method.
---@return string
M.get_sort_method = function()
  local sort_method = state.settings.discussion_tree.sort_by == "original_comment" and "↓ by thread" or "↑ by reply"
  return "%#GitlabSortMethod#" .. sort_method .. "%#Comment#"
end

---Return the winbar component for resolvable discussions.
---@param focused boolean Whether the particular section (Comments x Notes) is focused
---@param resolved_count integer The number of resolved discussions
---@param resolvable_count integer The total number of resolvable discussions
---@return string winbar_component
M.get_resolved_text = function(focused, resolved_count, resolvable_count)
  local text = focused and ("%#GitlabResolved#" .. state.settings.discussion_tree.resolved .. "%#Text#")
    or state.settings.discussion_tree.resolved
  return " " .. string.format("%d%s/%d", resolved_count, text, resolvable_count)
end

---Return the winbar component for draft discussions.
---@param base_title string
---@param drafts_count integer The number of draft discussions
---@param focused boolean Whether the particular section (Comments x Notes) is focused
---@return string winbar_component
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

---Return the winbar component for non-resolvable discussions.
---@param base_title string
---@param non_resolvable_count integer The number of non-resolvable discussions
---@param focused boolean Whether the particular section (Comments x Notes) is focused
---@return string winbar_component
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

---Return a string for the winbar indicating the mode type: live or draft.
---@return string
M.get_mode = function()
  if state.settings.discussion_tree.draft_mode then
    return "%#GitlabDraftMode#Draft"
  else
    return "%#GitlabLiveMode#Live"
  end
end

---Return the winbar component for number of ahead and behind commits.
---@param ahead? number
---@param behind? number
---@return string winbar_component
M.get_ahead_behind = function(ahead, behind)
  local a = ahead == nil and "?" or tostring(ahead)
  local b = behind == nil and "?" or tostring(behind)
  a = ((a == "?" or a == "0") and "%#Comment#" or "%#WarningMsg#") .. a
  b = ((b == "?" or b == "0") and "%#Comment#" or "%#WarningMsg#") .. b
  return a .. "↑ " .. b .. "↓"
end

---Set up a timer to update the winbar periodically.
M.start_timer = function()
  M.cleanup_timer()
  ---@type nil|uv_timer_t
  M.timer = vim.uv.new_timer()
  M.timer:start(0, 100, vim.schedule_wrap(M.update_winbar))
end

---Stop and close the timer.
M.cleanup_timer = function()
  if M.timer ~= nil then
    M.timer:stop()
    M.timer:close()
    M.timer = nil
  end
end

return M
