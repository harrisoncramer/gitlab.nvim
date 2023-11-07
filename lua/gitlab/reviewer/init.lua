local state = require("gitlab.state")
local diffview = require("gitlab.reviewer.diffview")

local M = {
  reviewer = nil,
}

local reviewer_map = {
  diffview = diffview,
}

M.init = function()
  local reviewer = reviewer_map[state.settings.reviewer]
  if reviewer == nil then
    vim.notify(
      string.format("gitlab.nvim could not find reviewer %s, only diffview is supported", state.settings.reviewer),
      vim.log.levels.ERROR
    )
    return
  end

  M.open = reviewer.open
  -- Opens the reviewer window

  M.jump = reviewer.jump
  -- Jumps to the location provided in the reviewer window
  -- Parameters:
  --   • {file_name}      The name of the file to jump to
  --   • {new_line}  The new_line of the change
  --   • {interval}  The old_line of the change

  M.get_location = reviewer.get_location
  -- Parameters:
  --   • {range}  LineRange if function was triggered from visual selection
  -- Returns the current location (based on cursor) from the reviewer window as ReviewerInfo class

  M.get_lines = reviewer.get_lines
  -- Returns the content of the file in the current location in the reviewer window

  M.get_current_file = reviewer.get_current_file
  -- Get currently loaded file

  M.place_sign = reviewer.place_sign
  -- Places a sign on the line for currently reviewed file.
  -- Parameters:
  --   • {id}    The sign id
  --   • {sign}  The sign to place
  --   • {group} The sign group to place on
  --   • {new_line}  The line to place the sign on
  --   • {old_line} The buffer number to place the sign on

  M.set_callback_for_file_changed = reviewer.set_callback_for_file_changed
  -- Call callback whenever the file changes
  -- Parameters:
  --   • {callback}  The callback to call

  M.set_callback_for_reviewer_leave = reviewer.set_callback_for_reviewer_leave
  -- Call callback whenever the reviewer is left
  -- Parameters:
  --   • {callback}  The callback to call

  M.set_diagnostics = reviewer.set_diagnostics
  -- Set diagnostics for currently reviewed file
  -- Parameters:
  --   • {namespace}    The namespace for diagnostics
  --   • {diagnostics}  The diagnostics to set
  --   • {type}         "new" if diagnostic should be in file after changes else "old"
  --   • {opts}         see opts in :h vim.diagnostic.set
end

return M
