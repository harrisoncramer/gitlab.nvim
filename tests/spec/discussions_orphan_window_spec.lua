-- close() closes the window itself instead of leaving that to NuiSplit, which gives up on
-- the last window of a session and ignores every later unmount once one has failed. These
-- tests check that the window and nui's own buffer are gone afterwards and that the
-- registry says so.

local discussions = require("gitlab.actions.discussions")
local draft_notes = require("gitlab.actions.draft_notes")
local windows = require("gitlab.actions.discussions.windows")

---Register a split with the given unmount behaviour, in a tabpage of its own.
---@param unmount fun(split: table)
---@return integer winid
---@return integer tabid
---@return integer split_bufnr The scratch buffer NuiSplit allocates on mount
local function arrange(unmount)
  vim.cmd("tabnew")
  vim.cmd("split")
  local winid = vim.api.nvim_get_current_win()
  local tabid = vim.api.nvim_get_current_tabpage()
  local split_bufnr = vim.api.nvim_create_buf(false, true)
  windows.set(tabid, {
    split = { winid = winid, bufnr = split_bufnr, unmount = unmount },
    winid = winid,
    bufnr = vim.api.nvim_get_current_buf(),
    view_type = "discussions",
  })
  return winid, tabid, split_bufnr
end

describe("actions/discussions.close", function()
  after_each(function()
    discussions.linked_bufnr = nil
    vim.cmd("tabnew")
    vim.cmd("silent! tabonly")
    vim.cmd("silent! only")
  end)

  it("Closes the window itself when a poisoned split ignores unmount", function()
    local winid, tabid, split_bufnr = arrange(function() end)

    discussions.close()

    assert.is_false(vim.api.nvim_win_is_valid(winid), ("window %d survived close()"):format(winid))
    assert.is_false(vim.api.nvim_buf_is_valid(split_bufnr), ("nui buffer %d survived close()"):format(split_bufnr))
    assert.is_nil(windows.get(tabid))
  end)

  it("Closes the window itself when unmounting raises", function()
    local winid, tabid, split_bufnr = arrange(function()
      error("nui teardown failed")
    end)

    discussions.close()

    assert.is_false(vim.api.nvim_win_is_valid(winid), ("window %d survived close()"):format(winid))
    assert.is_false(vim.api.nvim_buf_is_valid(split_bufnr), ("nui buffer %d survived close()"):format(split_bufnr))
    assert.is_nil(windows.get(tabid))
  end)

  it("Closes the window when it is the last one in the session", function()
    local winid, tabid = arrange(function() end)
    -- Neovim refuses to close the last window, so close() has to open a sibling first. That
    -- sibling shows the tree buffer, which is wiped a moment later.
    local bufnr = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_win_set_buf(winid, bufnr)
    discussions.linked_bufnr = bufnr
    vim.cmd("silent! tabonly")
    vim.cmd("silent! only")

    discussions.close()

    assert.is_false(vim.api.nvim_win_is_valid(winid), ("window %d survived close()"):format(winid))
    assert.is_false(vim.api.nvim_buf_is_valid(bufnr), ("buffer %d survived close()"):format(bufnr))
    assert.is_nil(windows.get(tabid))
  end)

  it("Tears the split down when the user closes the window by hand", function()
    -- M.open calls draft_notes.rebuild_view, which talks to the Go server these tests
    -- cannot connect to.
    local original_rebuild_view = draft_notes.rebuild_view
    draft_notes.rebuild_view = function() end
    vim.cmd("tabnew")
    discussions.open()
    local winid = windows.get().winid
    assert.is_not_nil(discussions.linked_bufnr, "M.open left no discussion buffer to release")

    vim.api.nvim_win_close(winid, true)

    -- The registry drops a dead window on its own, so the deferred teardown shows up
    -- elsewhere: the last window to close releases the discussion buffers.
    local released = vim.wait(200, function()
      return discussions.linked_bufnr == nil
    end, 10)
    draft_notes.rebuild_view = original_rebuild_view

    assert.is_true(released, "the discussion buffers are still listed 200ms after the window closed")
  end)
end)
