local discussions = require("gitlab.discussions")
local state       = require("gitlab.state")
local M           = {}

M.open            = function()
  vim.cmd.tabnew()

  local term_command_template =
  "GIT_PAGER='delta --hunk-header-style omit --line-numbers --paging never --diff-so-fancy --file-added-label %s --file-removed-label %s --file-modified-label %s' git diff --cached %s"

  local term_command = string.format(term_command_template, "", "", "", state.INFO.target_branch)
  vim.fn.termopen(term_command)

  vim.keymap.set('n', state.settings.review.toggle_discussions, function()
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
