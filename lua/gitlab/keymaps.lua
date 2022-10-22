local u             = require("gitlab.utils")
local state         = require("gitlab.state")
local M             = {}

M.set_popup_keymaps = function(popup, action)
  vim.keymap.set('n', state.keymaps.popup.exit, function() u.exit(popup) end, { buffer = true })
  vim.keymap.set('n', ':', '', { buffer = true })
  if action ~= nil then
    vim.keymap.set('n', state.keymaps.popup.perform_action, function()
      local text = u.get_buffer_text(popup.bufnr)
      popup:unmount()
      action(text)
    end, { buffer = true })
  end
end

M.set_keymap_keys   = function(keyTable)
  if keyTable == nil then return end
  state.keymaps = u.merge_tables(state.keymaps, keyTable)
end

return M
