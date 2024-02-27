local M = {}

M.has_clean_tree = function()
  local clean_tree = vim.fn.trim(vim.fn.system({ "git", "status", "--short", "--untracked-files=no" })) == ""
  return clean_tree
end

M.base_dir = function()
  return vim.fn.trim(vim.fn.system({ "git", "rev-parse", "--show-toplevel" }))
end

return M
