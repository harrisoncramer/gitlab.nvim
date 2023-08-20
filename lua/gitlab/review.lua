local discussions = require("gitlab.discussions")
local u           = require("gitlab.utils")
local state       = require("gitlab.state")
local M           = {}

M.open            = function()
  local review_buf = vim.fn.bufnr("gitlab.nvim", true)
  local tab_is_new = u.find_or_create_tab(review_buf)

  if not u.is_buffer_in_tab("gitlab.nvim") then
    vim.api.nvim_set_current_buf(review_buf)
  end

  if tab_is_new and vim.fn.line('$') == 1 then
    vim.fn.termopen("GIT_PAGER='delta --line-numbers --paging never' git diff " .. state.INFO.target_branch)
    vim.cmd("file gitlab.nvim")
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
end

return M
