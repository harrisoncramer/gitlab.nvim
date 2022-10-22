local state        = require("gitlab.state")
local Popup        = require("nui.popup")
local u            = require("gitlab.utils")
local keymaps      = require("gitlab.keymaps")
local summaryPopup = Popup(u.create_popup_state("Loading Summary...", "80%", "80%"))
local M            = {}

M.summary          = function()
  if u.base_invalid() then return end
  summaryPopup:mount()
  local currentBuffer = vim.api.nvim_get_current_buf()
  local title = state.INFO.title
  local description = state.INFO.description
  local lines = {}
  for line in description:gmatch("[^\n]+") do
    table.insert(lines, line)
    table.insert(lines, "")
  end
  vim.schedule(function()
    vim.api.nvim_buf_set_lines(currentBuffer, 0, -1, false, lines)
    vim.api.nvim_buf_set_option(currentBuffer, "modifiable", false)
    summaryPopup.border:set_text("top", title, "center")
    keymaps.set_popup_keymaps(summaryPopup)
  end)
end

return M
