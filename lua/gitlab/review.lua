local state = require("gitlab.state")
local M     = {}

M.open      = function()
  vim.fn.termopen("GIT_PAGER='delta --line-numbers --paging never' git diff " .. state.INFO.target_branch)
end

return M
