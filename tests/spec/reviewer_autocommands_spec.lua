-- The reviewer's window autocommands are buffer-local, and Diffview shares a revision's
-- buffer between the reviewer and the commit browser, so they also fire in the browser's
-- tab. There they must do nothing: the else branch would delete the browse keymaps and
-- make the blob writable.

describe("reviewer.set_reviewer_autocommands", function()
  local reviewer = require("gitlab.reviewer")
  local state = require("gitlab.state")

  it("Leaves the buffer alone outside the reviewer tab", function()
    local reviewer_tabid = vim.api.nvim_get_current_tabpage()
    vim.cmd("tabnew")
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(0, bufnr)
    vim.keymap.set("n", state.settings.keymaps.reviewer.create_comment, function() end, { buffer = bufnr })
    vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr })

    reviewer.tabid = reviewer_tabid
    reviewer.is_open = true
    -- Matching ids drive the else branch into its modifiable-and-unmap path, which the
    -- tab gate has to prevent from being reached at all.
    reviewer.diffview_layout = { b = { id = -1 } }
    reviewer.buf_winids[bufnr] = -1
    reviewer.set_reviewer_autocommands(bufnr)

    vim.api.nvim_exec_autocmds("WinEnter", { buffer = bufnr })

    assert.is_false(vim.api.nvim_get_option_value("modifiable", { buf = bufnr }))
    assert.are.equal(1, #vim.api.nvim_buf_get_keymap(bufnr, "n"))

    vim.cmd("tabclose")
    reviewer.tabid = nil
    reviewer.is_open = false
    reviewer.diffview_layout = nil
    reviewer.buf_winids[bufnr] = nil
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)
end)
