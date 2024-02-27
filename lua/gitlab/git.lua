local u = require("gitlab.utils")
local state = require("gitlab.state")
local M = {}

M.has_clean_tree = function()
  return vim.fn.trim(vim.fn.system({ "git", "status", "--short", "--untracked-files=no" })) == ""
end

M.base_dir = function()
  return vim.fn.trim(vim.fn.system({ "git", "rev-parse", "--show-toplevel" }))
end

return M
