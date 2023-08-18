local M      = {}

-- This is the global state that can be set from
-- various places in the plugin. It all begins as
-- uninitialized and is set by the setup/ensure function calls

M.BIN_PATH   = nil -- Directory of the Go binary
M.BIN        = nil -- Full path to the Go binary
M.PROJECT_ID = nil -- Gitlab Project ID, set in .gitlab.nvim file
M.INFO       = nil -- The basic information about the MR, set from "/info" endpoint

-- These are the default keymaps for the plugin
M.keymaps    = {
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
