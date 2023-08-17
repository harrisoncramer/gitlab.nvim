local M             = {}

M.BIN_PATH          = nil
M.BIN               = nil
M.PROJECT_ID        = nil
M.ACTIVE_DISCUSSION = nil
M.ACTIVE_NOTE       = nil
M.BASE_BRANCH       = "main"
M.keymaps           = {
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
