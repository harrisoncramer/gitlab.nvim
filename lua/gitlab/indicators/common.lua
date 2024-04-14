local u = require("gitlab.utils")
local state = require("gitlab.state")
local reviewer = require("gitlab.reviewer")
local List = require("gitlab.utils.list")

local M = {}

---@class NoteWithValues
---@field position NotePosition
---@field resolvable boolean|nil
---@field resolved boolean|nil
---@field created_at string|nil

---@param note NoteWithValues
---@param file string
---@return boolean
local filter_discussions_and_notes = function(note, file)
  return
    --Do not include unlinked notes
    note.position ~= nil
      and (note.position.new_path == file or note.position.old_path == file)
      --Skip resolved discussions if user wants to
      and not (state.settings.discussion_signs.skip_resolved_discussion and note.resolvable and note.resolved)
      --Skip discussions from old revisions
      and not (
        state.settings.discussion_signs.skip_old_revision_discussion
        and u.from_iso_format_date_to_timestamp(note.created_at)
          <= u.from_iso_format_date_to_timestamp(state.MR_REVISIONS[1].created_at)
      )
end

---Filter all discussions which are relevant for currently visible signs and diagnostics.
---@return Discussion|DraftNote[]
M.filter_placeable_discussions = function()
  if type(state.DISCUSSION_DATA.discussions) ~= "table" and type(state.DRAFT_NOTES) ~= "table" then
    return {}
  end

  local file = reviewer.get_current_file()
  if not file then
    return {}
  end

  local filtered_discussions = List.new(state.DISCUSSION_DATA.discussions):filter(function(discussion)
    local first_note = discussion.notes[1]
    return type(first_note.position) == "table" and filter_discussions_and_notes(first_note, file)
  end)

  local filtered_draft_notes = List.new(state.DRAFT_NOTES):filter(function(note)
    return filter_discussions_and_notes(note, file)
  end)

  return u.join(filtered_discussions, filtered_draft_notes)
end

M.parse_line_code = function(line_code)
  local line_code_regex = "%w+_(%d+)_(%d+)"
  local old_line, new_line = line_code:match(line_code_regex)
  return tonumber(old_line), tonumber(new_line)
end

---@param d_or_n Discussion|DraftNote
---@return boolean
M.is_old_sha = function(d_or_n)
  local first_note = M.get_first_note(d_or_n)
  return first_note.position.old_line ~= nil
end

---@param discussion Discussion|DraftNote
---@return boolean
M.is_new_sha = function(discussion)
  return not M.is_old_sha(discussion)
end

---@param d_or_n Discussion|DraftNote
---@return boolean
M.is_single_line = function(d_or_n)
  local first_note = M.get_first_note(d_or_n)
  local line_range = first_note.position and first_note.position.line_range
  return line_range == nil
end

---@param discussion Discussion
---@return boolean
M.is_multi_line = function(discussion)
  return not M.is_single_line(discussion)
end

---@param d_or_n Discussion|DraftNote
---@return Note|DraftNote
M.get_first_note = function(d_or_n)
  return d_or_n.notes and d_or_n.notes[1] or d_or_n
end

return M
