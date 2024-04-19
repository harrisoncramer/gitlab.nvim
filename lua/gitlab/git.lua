local M = {}

M.has_clean_tree = function()
  return vim.fn.trim(vim.fn.system({ "git", "status", "--short", "--untracked-files=no" })) == ""
end

M.base_dir = function()
  return vim.fn.trim(vim.fn.system({ "git", "rev-parse", "--show-toplevel" }))
end

M.switch_branch = function(branch)
  return vim.fn.trim(vim.fn.system({ "git", "checkout", "-q", branch }))
end

return M
