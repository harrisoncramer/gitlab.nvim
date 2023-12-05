local M = {}

-- Updates the winbars for the notes and discussions sections
M.update_winbars = function(unlinked_section_bufnr, linked_section_bufnr)
  vim.api.nvim_buf_set_name(unlinked_section_bufnr, "Notes")
  vim.api.nvim_buf_set_name(linked_section_bufnr, "Discussions")
  local w1 = vim.fn.bufwinid(unlinked_section_bufnr)
  vim.wo[w1].winbar = "%f"
  local w2 = vim.fn.bufwinid(linked_section_bufnr)
  vim.wo[w2].winbar = "%f"
end

return M
