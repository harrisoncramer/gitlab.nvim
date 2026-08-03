-- close() closes the window itself instead of leaving that to NuiSplit, which gives up on
-- the last window of a session and ignores every later unmount once one has failed. These
-- tests check that the window and nui's own buffer are gone afterwards and that
-- `split_visible` says so.

local discussions = require("gitlab.actions.discussions")
local draft_notes = require("gitlab.actions.draft_notes")
local winbar = require("gitlab.actions.discussions.winbar")
local state = require("gitlab.state")

---Register a split with the given unmount behaviour, in a window of its own.
---@param unmount fun(split: table)
---@return integer winid
---@return integer bufnr The scratch buffer NuiSplit allocates on mount
local function arrange(unmount)
  vim.cmd("tabnew")
  vim.cmd("split")
  local winid = vim.api.nvim_get_current_win()
  local bufnr = vim.api.nvim_create_buf(false, true)
  discussions.split = { winid = winid, bufnr = bufnr, unmount = unmount }
  discussions.split_visible = true
  return winid, bufnr
end

describe("actions/discussions.close", function()
  after_each(function()
    discussions.split = nil
    discussions.split_visible = false
    discussions.discussion_tree = nil
    discussions.linked_bufnr = nil
    discussions.unlinked_bufnr = nil
    winbar.cleanup_timer()
    state.DISCUSSION_DATA = nil
    vim.cmd("tabnew")
    vim.cmd("silent! tabonly")
    vim.cmd("silent! only")
  end)

  it("Closes the window itself when a poisoned split ignores unmount", function()
    local winid, bufnr = arrange(function() end)

    discussions.close()

    assert.is_false(vim.api.nvim_win_is_valid(winid), ("window %d survived close()"):format(winid))
    assert.is_false(vim.api.nvim_buf_is_valid(bufnr), ("nui buffer %d survived close()"):format(bufnr))
    assert.is_false(discussions.split_visible)
  end)

  it("Closes the window itself when unmounting raises", function()
    local winid, bufnr = arrange(function()
      error("nui teardown failed")
    end)

    discussions.close()

    assert.is_false(vim.api.nvim_win_is_valid(winid), ("window %d survived close()"):format(winid))
    assert.is_false(vim.api.nvim_buf_is_valid(bufnr), ("nui buffer %d survived close()"):format(bufnr))
    assert.is_false(discussions.split_visible)
  end)

  it("Closes the window when it is the last one in the session", function()
    vim.cmd("silent! tabonly")
    vim.cmd("silent! only")
    -- Neovim refuses to close the last window, so close() has to open a sibling first. That
    -- sibling shows the tree buffer, which is wiped a moment later.
    local winid = vim.api.nvim_get_current_win()
    local bufnr = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_win_set_buf(winid, bufnr)
    discussions.split = { winid = winid, unmount = function() end }
    discussions.split_visible = true
    discussions.linked_bufnr = bufnr

    discussions.close()

    assert.is_false(vim.api.nvim_win_is_valid(winid), ("window %d survived close()"):format(winid))
    assert.is_false(vim.api.nvim_buf_is_valid(bufnr), ("buffer %d survived close()"):format(bufnr))
    assert.is_false(discussions.split_visible)
  end)

  it("Tears the split down when the user closes the window by hand", function()
    -- M.open calls draft_notes.rebuild_view, which talks to the Go server these tests
    -- cannot connect to.
    local original_rebuild_view = draft_notes.rebuild_view
    draft_notes.rebuild_view = function() end
    vim.cmd("tabnew")
    discussions.open()
    local winid = discussions.split.winid

    vim.api.nvim_win_close(winid, true)

    local torn_down = vim.wait(200, function()
      return discussions.split_visible == false
    end, 10)

    assert.is_true(torn_down, "split_visible is still set 200ms after the window closed")
    draft_notes.rebuild_view = original_rebuild_view
  end)
end)
