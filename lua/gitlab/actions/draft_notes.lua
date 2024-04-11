local state = require("gitlab.state")
local help = require("gitlab.actions.help")
local winbar = require("gitlab.actions.discussions.winbar")

local M = {
  bufnr = nil
}

--- Adds a draft note to the draft notes view in the review panel
--- @param draft_note DraftNote
M.add_draft_note = function(draft_note)
  vim.print(draft_note)
end

--- @param bufnr integer
M.set_bufnr = function(bufnr)
  M.bufnr = bufnr
end

M.rebuild_draft_notes_view = function()
  M.set_keymaps(true)
end

M.set_keymaps = function(unlinked)
  vim.keymap.set("n", state.settings.discussion_tree.edit_comment, function()
    M.edit_comment()
  end, { buffer = M.bufnr, desc = "Edit comment" })
  vim.keymap.set("n", state.settings.discussion_tree.delete_comment, function()
    M.delete_comment()
  end, { buffer = M.bufnr, desc = "Delete comment" })
  vim.keymap.set("n", state.settings.discussion_tree.switch_view, function()
    winbar.switch_view_type()
  end, { buffer = M.bufnr, desc = "Switch view type" })
  vim.keymap.set("n", state.settings.help, function()
    help.open()
  end, { buffer = M.bufnr, desc = "Open help popup" })
  if not unlinked then
    vim.keymap.set("n", state.settings.discussion_tree.jump_to_file, function()
      M.jump_to_file()
    end, { buffer = M.bufnr, desc = "Jump to file" })
    vim.keymap.set("n", state.settings.discussion_tree.jump_to_reviewer, function()
      M.jump_to_reviewer()
    end, { buffer = M.bufnr, desc = "Jump to reviewer" })
  end
  vim.keymap.set("n", state.settings.discussion_tree.open_in_browser, function()
    M.open_in_browser()
  end, { buffer = M.bufnr, desc = "Open the note in your browser" })
  vim.keymap.set("n", state.settings.discussion_tree.copy_node_url, function()
    M.copy_node_url()
  end, { buffer = M.bufnr, desc = "Copy the URL of the current node to clipboard" })
  vim.keymap.set("n", "<leader>p", function()
    M.print_node()
  end, { buffer = M.bufnr, desc = "Print current node (for debugging)" })
end

return M
