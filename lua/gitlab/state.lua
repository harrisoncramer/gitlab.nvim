local M   = {}

-- These are the default keymaps for the plugin
M.keymaps = {
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
    toggle_resolved = "p"
  },
  dialogue = {
    focus_next = { "j", "<Down>", "<Tab>" },
    focus_prev = { "k", "<Up>", "<S-Tab>" },
    close = { "<Esc>", "<C-c>" },
    submit = { "<CR>", "<Space>" },
  },
  review = {
    toggle = "<leader>glt"
  }
}

return M
