local discussions = require("gitlab.discussions")
local state       = require("gitlab.state")
local M           = {}

M.open            = function()
  vim.cmd.tabnew()

  local term_command_template =
  "GIT_PAGER='delta --hunk-header-style omit --line-numbers --paging never --file-added-label %s --file-removed-label %s --file-modified-label %s' git diff %s...HEAD"

  local term_command = string.format(term_command_template,
    state.settings.review_pane.added_file,
    state.settings.review_pane.removed_file,
    state.settings.review_pane.modified_file,
    state.INFO.target_branch)

  vim.fn.termopen(term_command) -- Calls delta and sends the output to the currently blank buffer
  state.REVIEW_BUF = vim.api.nvim_get_current_buf()

  vim.keymap.set('n', state.settings.review_pane.toggle_discussions, function()
    if not discussions.split then return end
    if discussions.split_visible then
      discussions.split:hide()
      discussions.split_visible = false
    else
      discussions.split:show()
      discussions.split_visible = true
    end
  end)
  discussions.list_discussions()
end

return M
