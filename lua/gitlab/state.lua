local u             = require("gitlab.utils")
local M             = {}

-- These are the default settings for the plugin
M.settings          = {
  port = 21036,
  log_path = (vim.fn.stdpath("cache") .. "/gitlab.nvim.log"),
  popup = {
    exit = "<Esc>",
    perform_action = "<leader>s",
  },
  discussion_tree = {
    jump_to_location = "o",
    edit_comment = "e",
    delete_comment = "dd",
    reply_to_comment = "r",
    toggle_node = "t",
    toggle_resolved = "p",
    relative = "editor",
    position = "left",
    size = "20%",
    resolved = '✓',
    unresolved = ''
  },
  review_pane = {
    toggle_discussions = "<leader>d",
    added_file = "",
    modified_file = "",
    removed_file = "",
  },
  dialogue = {
    focus_next = { "j", "<Down>", "<Tab>" },
    focus_prev = { "k", "<Up>", "<S-Tab>" },
    close = { "<Esc>", "<C-c>" },
    submit = { "<CR>", "<Space>" },
  },
}

-- Merges user settings into the default settings, overriding them
M.merge_settings    = function(keyTable)
  if keyTable == nil then return end
  M.settings = u.merge_tables(M.settings, keyTable)
end

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


return M
