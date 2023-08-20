local M    = {}

-- These are the default settings for the plugin
M.settings = {
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

return M
