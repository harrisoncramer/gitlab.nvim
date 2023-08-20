local u             = require("gitlab.utils")
local state         = require("gitlab.state")
local M             = {}

-- Sets the settings for the popup window that's used for replies, the summary, etc
M.set_popup_keymaps = function(popup, action)
  vim.keymap.set('n', state.settings.popup.exit, function() u.exit(popup) end, { buffer = true })
  if action ~= nil then
    vim.keymap.set('n', state.settings.popup.perform_action, function()
      local text = u.get_buffer_text(popup.bufnr)
      popup:unmount()
      action(text)
    end, { buffer = true })
  end
end

M.merge_settings    = function(keyTable)
  if keyTable == nil then return end
  state.settings = u.merge_tables(state.settings, keyTable)
end

return M
