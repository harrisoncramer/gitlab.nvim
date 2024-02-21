local M = {}

local u = require("gitlab.utils")
local state = require("gitlab.state")
local Popup = require("nui.popup")

M.open = function()
  local bufnr = vim.api.nvim_get_current_buf()
  local keymaps = vim.api.nvim_buf_get_keymap(bufnr, "n")
  local help_content_lines = List.new(keymaps):reduce(function(agg, keymap)
    if keymap.desc ~= nil then
      local new_line = string.format("%s: %s", keymap.lhs:gsub(" ", "<space>"), keymap.desc)
      table.insert(agg, new_line)
    end
    return agg
  end, {})
  local longest_line = u.get_longest_string(help_content_lines)
  local help_popup =
    Popup(u.create_popup_state("Help", state.settings.popup.help, longest_line + 3, #help_content_lines + 3, 60))
  help_popup:mount()

  state.set_popup_keymaps(help_popup, "Help", nil)
  local currentBuffer = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(currentBuffer, 0, #help_content_lines, false, help_content_lines)
end

return M
