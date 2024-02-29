local u = require("gitlab.utils")
local state = require("gitlab.state")
local reviewer = require("gitlab.reviewer")
local List = require("gitlab.utils.list")

local M = {}

---Filter all discussions which are relevant for currently visible signs and diagnostics.
---@return Discussion[]
M.filter_discussions = function(all_discussions)
  if type(all_discussions) ~= "table" then
    return {}
  end
  local file = reviewer.get_current_file()
  if not file then
    return {}
  end
  return List.new(all_discussions):filter(function(discussion)
    local first_note = discussion.notes[1]
    return type(first_note.position) == "table"
        --Do not include unlinked notes
        and (first_note.position.new_path == file or first_note.position.old_path == file)
        --Skip resolved discussions if user wants to
        and
        not (state.settings.discussion_sign_and_diagnostic.skip_resolved_discussion and first_note.resolvable and first_note.resolved)
        --Skip discussions from old revisions
        and not (
          state.settings.discussion_sign_and_diagnostic.skip_old_revision_discussion
          and u.from_iso_format_date_to_timestamp(first_note.created_at)
          <= u.from_iso_format_date_to_timestamp(state.MR_REVISIONS[1].created_at)
        )
  end)
end


return M
