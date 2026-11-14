-- Tests for reviewer/history.lua select_commit. When the target commit's file list has no
-- match for the file being followed (e.g. after a rename earlier in the history), the jump
-- must warn instead of silently opening an unrelated file. select_commit also has to focus
-- the new-side window, or the cursor jump leaves the caller's window focused.

local history = require("gitlab.reviewer.history")

describe("reviewer/history.lua select_commit", function()
  it("Does not jump and warns when the target commit does not touch the followed file", function()
    local view = {
      panel = {
        entries = {
          { commit = { hash = "sha1" }, files = { { path = "unrelated.lua" } } },
        },
      },
      set_file = function()
        error("select_commit must not open a file when there is no match")
      end,
    }

    local u = require("gitlab.utils")
    local original_notify = u.notify
    local notified
    u.notify = function(msg, lvl)
      notified = { msg = msg, lvl = lvl }
    end

    history.select_commit(view, "sha1", "original.lua", 10)

    u.notify = original_notify

    assert.is_not_nil(notified)
    assert.are.equal("Commit does not touch this file", notified.msg)
  end)

  it("Focuses the new-side window, so the cursor jump actually lands there", function()
    local focused = false
    local bufnr = vim.api.nvim_create_buf(false, true)

    local view = {
      panel = {
        entries = {
          { commit = { hash = "sha1" }, files = { { path = "f.lua" } } },
        },
      },
      set_file = function()
        return { await = function() end }
      end,
      cur_layout = {
        b = {
          focus = function()
            focused = true
          end,
          file = { bufnr = bufnr },
        },
      },
    }

    history.select_commit(view, "sha1", "f.lua", 3)

    assert.is_true(focused)

    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)
end)

describe("reviewer/history.lua jump_to_commit", function()
  it("Waits for Diffview's own initial file selection before picking a target commit", function()
    local reviewer = require("gitlab.reviewer")
    local diffview_lib = require("diffview.lib")

    local original_browse_commits = reviewer.browse_commits
    local original_get_current_view = diffview_lib.get_current_view
    local original_select_commit = history.select_commit
    local original_history_tabid = reviewer.history_tabid

    local tabid = vim.api.nvim_get_current_tabpage()
    reviewer.history_tabid = tabid
    reviewer.browse_commits = function() end

    -- Diffview's panel already has entries from the start; only `cur_file()` lags,
    -- mirroring the initial-selection race M.jump_to_commit waits out.
    local view = {
      panel = {
        entries = { { commit = { hash = "sha1" }, files = { { path = "f.lua" } } } },
        cur_item = nil,
      },
    }
    function view.panel:cur_file()
      return self.cur_item
    end

    diffview_lib.get_current_view = function()
      return view
    end

    local cur_item_was_set_before_select
    history.select_commit = function()
      cur_item_was_set_before_select = view.panel.cur_item ~= nil
    end

    -- Simulate Diffview's own initial selection landing shortly after the wait starts.
    vim.defer_fn(function()
      view.panel.cur_item = {}
    end, 100)

    history.jump_to_commit("sha1", "f.lua", 3)

    reviewer.browse_commits = original_browse_commits
    diffview_lib.get_current_view = original_get_current_view
    history.select_commit = original_select_commit
    reviewer.history_tabid = original_history_tabid

    assert.is_true(cur_item_was_set_before_select)
  end)
end)
