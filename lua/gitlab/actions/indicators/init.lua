local diagnostics = require("gitlab.actions.indicators.diagnostics")
local signs = require("gitlab.actions.indicators.signs")

local M = {}
M.clear_signs_and_diagnostics = function()
  vim.fn.sign_unplace(signs.discussion_sign_name)
  vim.diagnostic.reset(diagnostics.diagnostics_namespace)
end

M.diagnostics = diagnostics
M.signs = signs

return M
