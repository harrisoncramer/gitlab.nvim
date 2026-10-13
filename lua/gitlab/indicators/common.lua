local u = require("gitlab.utils")
local state = require("gitlab.state")
local List = require("gitlab.utils.list")

local M = {}

---@class NoteWithValues
---@field position NotePosition
---@field resolvable? boolean
---@field resolved? boolean
---@field created_at? string

-- Display options for the diagnostic
M.create_display_opts = function()
  return {
    virtual_text = state.settings.discussion_signs.virtual_text,
    severity_sort = true,
    underline = false,
    signs = state.settings.discussion_signs.use_diagnostic_signs,
  }
end

---Return true if discussion has a placeable diagnostic, false otherwise.
---@param note NoteWithValues
---@return boolean
local filter_discussions_and_notes = function(note)
  ---Do not include unlinked notes
  return note.position ~= nil
    ---Skip resolved discussions if user wants to
    and not (state.settings.discussion_signs.skip_resolved_discussion and note.resolvable and note.resolved)
    ---Skip discussions from old revisions
    and not (
      state.settings.discussion_signs.skip_old_revision_discussion
      and note.created_at ~= nil
      and u.from_iso_format_date_to_timestamp(note.created_at)
        <= u.from_iso_format_date_to_timestamp(state.MR_REVISIONS[1].created_at)
    )
end

---Filter all discussions and drafts which have placeable signs and diagnostics.
---@return (Discussion|DraftNote)[]
M.filter_placeable_discussions = function()
  local discussions = u.ensure_table(state.DISCUSSION_DATA and state.DISCUSSION_DATA.discussions or {})
  if type(discussions) ~= "table" then
    discussions = {}
  end

  local draft_notes = u.ensure_table(state.DRAFT_NOTES)
  if type(draft_notes) ~= "table" then
    draft_notes = {}
  end

  local filtered_discussions = List.new(discussions):filter(function(discussion)
    local first_note = discussion.notes[1]
    return type(first_note.position) == "table" and filter_discussions_and_notes(first_note)
  end)

  local filtered_draft_notes = List.new(draft_notes):filter(function(note)
    return filter_discussions_and_notes(note)
  end)

  return u.join(filtered_discussions, filtered_draft_notes)
end

---Parse old and new line from a line code like "3f454a98e586d1aa0d322e19afd5e67e08f2d3c8_10_44".
---@param line_code string A SHA hash of the file name and line numbers before and after change
---@return integer The line number before the change
---@return integer The line number after the change
M.parse_line_code = function(line_code)
  local line_code_regex = "%w+_(%d+)_(%d+)"
  local old_line, new_line = line_code:match(line_code_regex)
  old_line = tonumber(old_line) --[[@as integer]]
  new_line = tonumber(new_line) --[[@as integer]]
  return old_line, new_line
end

---Return true if discussion/draft belongs to the old file, otherwise false.
---@param d_or_n Discussion|DraftNote
---@return boolean
M.is_old_sha = function(d_or_n)
  local position = M.get_first_note(d_or_n).position
  local old_start_line = position.line_range ~= nil and M.parse_line_code(position.line_range.start.line_code) or nil
  -- FIXME: Update how `old_start_line ~= 0` is evaluated. After the Location refactor,
  -- the numbers in line codes never are set to 0, but we should support the old way of
  -- determining "is_old_sha" at least for some time because users will encounter the
  -- old values in existing discussion nodes created with the old version of the plugin.
  -- This should also check if the type of the range location(s) is "old".
  return position.old_line ~= nil and old_start_line ~= 0
end

---Return true if discussion/draft belongs to the new file, otherwise false.
---@param discussion Discussion|DraftNote
---@return boolean
M.is_new_sha = function(discussion)
  return not M.is_old_sha(discussion)
end

---Return true if the discussion/draft doesn't have a line range.
---@param d_or_n Discussion|DraftNote
---@return boolean
M.is_single_line = function(d_or_n)
  local first_note = M.get_first_note(d_or_n)
  local line_range = first_note.position and first_note.position.line_range
  return line_range == nil
end

---Return the first note from a Discussion thread or the DraftNote.
---@param d_or_n Discussion|DraftNote
---@return Note|DraftNote
M.get_first_note = function(d_or_n)
  return d_or_n.notes and d_or_n.notes[1] or d_or_n
end

return M
