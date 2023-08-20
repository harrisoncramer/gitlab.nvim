local discussions = require("gitlab.discussions")
local u           = require("gitlab.utils")
local state       = require("gitlab.state")
local M           = {}

M.open            = function()
  vim.cmd.tabnew()
  vim.fn.termopen(
    "GIT_PAGER='delta --hunk-header-style omit --line-numbers --paging never --diff-so-fancy --file-added-label  --file-removed-label  --file-modified-label ' git diff --cached " ..
    state.INFO.target_branch)
  vim.keymap.set('n', state.keymaps.review.toggle_discussions, function()
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
