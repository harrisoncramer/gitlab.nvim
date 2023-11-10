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
end

return M
