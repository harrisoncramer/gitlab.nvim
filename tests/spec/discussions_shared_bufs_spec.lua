-- The linked and unlinked buffers are shared by every discussion window but not by the
-- session: the first open creates them, the last close owns their release.

local discussions = require("gitlab.actions.discussions")
local draft_notes = require("gitlab.actions.draft_notes")
local windows = require("gitlab.actions.discussions.windows")
local winbar = require("gitlab.actions.discussions.winbar")
local state = require("gitlab.state")

-- Without this precondition the deletion asserts below would also pass if open() never
-- created the buffers in the first place.
local function assert_buffers_created(linked, unlinked)
  assert.is_true(linked ~= nil and vim.api.nvim_buf_is_valid(linked), "open() created no linked buffer")
  assert.is_true(unlinked ~= nil and vim.api.nvim_buf_is_valid(unlinked), "open() created no unlinked buffer")
end

describe("actions/discussions buffers", function()
  local original_rebuild_view

  before_each(function()
    -- M.open tails into draft_notes.rebuild_view, which talks to the Go server these tests
    -- have no connection to.
    original_rebuild_view = draft_notes.rebuild_view
    draft_notes.rebuild_view = function() end
  end)

  after_each(function()
    draft_notes.rebuild_view = original_rebuild_view
    discussions.discussion_tree = nil
    discussions.linked_bufnr = nil
    discussions.unlinked_bufnr = nil
    winbar.cleanup_timer()
    state.DISCUSSION_DATA = nil
    vim.cmd("tabnew")
    vim.cmd("silent! tabonly")
    vim.cmd("silent! only")
  end)

  it("Deletes both buffers when the window is closed", function()
    vim.cmd("tabnew")
    discussions.open()
    local linked, unlinked = discussions.linked_bufnr, discussions.unlinked_bufnr
    assert_buffers_created(linked, unlinked)

    discussions.close()

    assert.is_false(vim.api.nvim_buf_is_valid(linked), ("linked buffer %d was not deleted"):format(linked))
    assert.is_false(vim.api.nvim_buf_is_valid(unlinked), ("unlinked buffer %d was not deleted"):format(unlinked))
  end)

  it("Leaves no buffer behind over an open/close cycle", function()
    vim.cmd("tabnew")
    discussions.open()
    local first_linked, first_unlinked = discussions.linked_bufnr, discussions.unlinked_bufnr
    assert_buffers_created(first_linked, first_unlinked)
    discussions.close()

    discussions.open()

    assert.are_not.equal(first_linked, discussions.linked_bufnr)
    assert.is_false(
      vim.api.nvim_buf_is_valid(first_linked),
      ("linked buffer %d of the first open leaked"):format(first_linked)
    )
    assert.is_false(
      vim.api.nvim_buf_is_valid(first_unlinked),
      ("unlinked buffer %d of the first open leaked"):format(first_unlinked)
    )
    discussions.close()
  end)

  it("Keeps the buffers while another tab still shows them", function()
    vim.cmd("tabnew")
    discussions.open()
    local linked, unlinked = discussions.linked_bufnr, discussions.unlinked_bufnr
    vim.cmd("tabnew")
    discussions.open()

    discussions.close()

    assert.is_true(vim.api.nvim_buf_is_valid(linked), ("linked buffer %d was pulled from the other tab"):format(linked))
    assert.is_true(
      vim.api.nvim_buf_is_valid(unlinked),
      ("unlinked buffer %d was pulled from the other tab"):format(unlinked)
    )
  end)

  it("Deletes both buffers when the user closes the last window by hand", function()
    vim.cmd("tabnew")
    discussions.open()
    local linked = discussions.linked_bufnr

    vim.api.nvim_win_close(windows.get().winid, true)

    local released = vim.wait(200, function()
      return not vim.api.nvim_buf_is_valid(linked)
    end, 10)

    assert.is_true(released, ("linked buffer %d is still alive 200ms after the window closed"):format(linked))
  end)
end)
