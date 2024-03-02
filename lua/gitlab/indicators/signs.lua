local state = require("gitlab.state")
local discussion_sign_name = require("gitlab.indicators.diagnostics").discussion_sign_name
local namespace = require("gitlab.indicators.diagnostics").diagnostics_namespace

local M = {}
M.clear_signs = function()
  vim.fn.sign_unplace(discussion_sign_name)
end

local severity_map = {
  "Error",
  "Warn",
  "Info",
  "Hint"
}

---Refresh the discussion signs for currently loaded file in reviewer For convinience we use same
---string for sign name and sign group ( currently there is only one sign needed)
---@param diagnostics Diagnostic[]
---@param bufnr number
M.set_signs = function(diagnostics, bufnr)
  if not state.settings.discussion_sign.enabled then
    return
  end

  -- Filter diagnostics from the 'gitlab' source and apply custom signs
  for _, diagnostic in ipairs(diagnostics) do
    local sign_id = string.format("%s__%d", namespace, diagnostic.lnum)
    vim.fn.sign_place(sign_id, discussion_sign_name, 'DiagnosticSign' .. M.severity .. 'Gitlab', bufnr,
      { lnum = diagnostic.lnum + 1, priority = 999999 })
  end
end

---Define signs for discussions if not already defined
M.setup_signs = function()
  local discussion_sign_settings = state.settings.discussion_signs
  local icon = discussion_sign_settings.icon
  M.severity = severity_map[state.settings.discussion_signs.severity]
  local signs = { "Error", "Warn", "Hint", "Info" }
  for _, type in ipairs(signs) do
    local hl = "DiagnosticSign" .. type
    local custom_hl = hl .. "Gitlab"
    vim.fn.sign_define(custom_hl, {
      text = icon,
      texthl = custom_hl
    })
    vim.cmd(string.format("highlight link %s %s", custom_hl, hl))
  end
end

return M
