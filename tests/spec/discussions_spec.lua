describe("gitlab/actions/discussions/init.lua", function()
  it("Loads package", function()
    local utils_ok, _ = pcall(require, "gitlab.actions.discussions")
    assert._is_true(utils_ok)
  end)

  describe("multi-tab window handling", function()
    local discussions = require("gitlab.actions.discussions")
    local windows = require("gitlab.actions.discussions.windows")
    local draft_notes = require("gitlab.actions.draft_notes")
    local winbar = require("gitlab.actions.discussions.winbar")
    local state = require("gitlab.state")
    local original_rebuild_view

    before_each(function()
      -- M.open's tail calls into draft_notes.rebuild_view to fetch fresh data from the Go
      -- server, which these tests aren't exercising and have no server to talk to.
      original_rebuild_view = draft_notes.rebuild_view
      draft_notes.rebuild_view = function() end
    end)

    after_each(function()
      draft_notes.rebuild_view = original_rebuild_view
      -- `tabonly` never closes the *current* tab, so hop to a fresh one first to make sure
      -- every discussion window opened by the test (incl. the one in the tab we ended on)
      -- actually closes and prunes its registry entry via the real WinClosed path.
      vim.cmd("tabnew")
      vim.cmd("silent! tabonly")
      winbar.cleanup_timer()
      discussions.linked_bufnr = nil
      discussions.unlinked_bufnr = nil
      discussions.discussion_tree = nil
      discussions.unlinked_discussion_tree = nil
      state.DISCUSSION_DATA = nil
    end)

    it("Open() in a second tab adds a second window entry without creating new buffers", function()
      vim.cmd("tabnew")
      local tab_a = vim.api.nvim_get_current_tabpage()
      discussions.open()
      local linked_bufnr, unlinked_bufnr = discussions.linked_bufnr, discussions.unlinked_bufnr

      vim.cmd("tabnew")
      local tab_b = vim.api.nvim_get_current_tabpage()
      discussions.open()

      local entry_a = windows.get(tab_a)
      local entry_b = windows.get(tab_b)
      assert.is_not_nil(entry_a)
      assert.is_not_nil(entry_b)
      assert.is_true(entry_a.winid ~= entry_b.winid)
      assert.are.equal(linked_bufnr, discussions.linked_bufnr)
      assert.are.equal(unlinked_bufnr, discussions.unlinked_bufnr)
    end)

    it("Switch_view_type only changes the current tab's window", function()
      vim.cmd("tabnew")
      local tab_a = vim.api.nvim_get_current_tabpage()
      discussions.open()
      local entry_a = windows.get(tab_a)

      vim.cmd("tabnew")
      local tab_b = vim.api.nvim_get_current_tabpage()
      discussions.open()
      local entry_b = windows.get(tab_b)

      vim.api.nvim_set_current_tabpage(tab_a)
      discussions.switch_view_type("notes")

      assert.are.equal(discussions.unlinked_bufnr, vim.api.nvim_win_get_buf(entry_a.winid))
      assert.are.equal("notes", entry_a.view_type)
      assert.are.equal(discussions.linked_bufnr, vim.api.nvim_win_get_buf(entry_b.winid))
      assert.are.equal("discussions", entry_b.view_type)
    end)

    it("Toggling the view type (no override) in one tab doesn't skip the toggle in another", function()
      -- Regression: the decision used to hang off a module-global "current view type", so
      -- toggling tab A to "notes" made tab B's own (unrelated) toggle press a no-op.
      vim.cmd("tabnew")
      local tab_a = vim.api.nvim_get_current_tabpage()
      discussions.open()

      vim.cmd("tabnew")
      local tab_b = vim.api.nvim_get_current_tabpage()
      discussions.open()
      local entry_b = windows.get(tab_b)

      vim.api.nvim_set_current_tabpage(tab_a)
      discussions.switch_view_type() -- tab A: discussions -> notes

      vim.api.nvim_set_current_tabpage(tab_b)
      discussions.switch_view_type() -- tab B: discussions -> notes, independent of tab A

      assert.are.equal("notes", entry_b.view_type)
      assert.are.equal(discussions.unlinked_bufnr, vim.api.nvim_win_get_buf(entry_b.winid))
    end)

    it("Close(tabid) unmounts that tab's window even when it isn't the current tab", function()
      vim.cmd("tabnew")
      local target_tab = vim.api.nvim_get_current_tabpage()
      discussions.open()
      local entry = windows.get(target_tab)

      vim.cmd("tabnew") -- move away from target_tab before closing it

      discussions.close(target_tab)

      assert.is_nil(windows.get(target_tab))
      assert.is_false(vim.api.nvim_win_is_valid(entry.winid))
    end)

    it("Close_all() unmounts every registered window across all tabs", function()
      vim.cmd("tabnew")
      local tab_a = vim.api.nvim_get_current_tabpage()
      discussions.open()
      local entry_a = windows.get(tab_a)

      vim.cmd("tabnew")
      local tab_b = vim.api.nvim_get_current_tabpage()
      discussions.open()

      discussions.close_all()

      assert.is_nil(windows.get(tab_a))
      assert.is_nil(windows.get(tab_b))
      assert.is_false(vim.api.nvim_win_is_valid(entry_a.winid))
      assert.is_nil(winbar.timer)
    end)

    it("Closing the window by hand releases the split's own buffer", function()
      vim.cmd("tabnew")
      discussions.open()
      local entry = windows.get()
      local split_bufnr = entry.split.bufnr
      assert.is_true(vim.api.nvim_buf_is_valid(split_bufnr))

      vim.api.nvim_win_close(entry.winid, true)

      assert.is_true(vim.wait(200, function()
        return not vim.api.nvim_buf_is_valid(split_bufnr)
      end, 10))
    end)

    it("Closing one tab's discussion window (WinClosed) removes only that tab's entry", function()
      vim.cmd("tabnew")
      local tab_a = vim.api.nvim_get_current_tabpage()
      discussions.open()
      local entry_a = windows.get(tab_a)

      vim.cmd("tabnew")
      local tab_b = vim.api.nvim_get_current_tabpage()
      discussions.open()
      local entry_b = windows.get(tab_b)

      vim.api.nvim_win_close(entry_b.winid, true)

      assert.is_nil(windows.get(tab_b))
      assert.is_not_nil(windows.get(tab_a))
      assert.is_not_nil(winbar.timer)

      vim.api.nvim_win_close(entry_a.winid, true)

      assert.is_nil(windows.get(tab_a))
      assert.is_nil(winbar.timer)
    end)

    it("Rebuild_discussion_tree restores each tab's own cursor node, not another tab's", function()
      state.INFO = { web_url = "https://gitlab.com/some-org/-/merge_requests/1" }
      state.settings.discussion_tree.tree_type = "simple"
      local function make_discussion(id, note_id, body)
        return {
          id = id,
          individual_note = false,
          notes = {
            {
              id = note_id,
              author = { username = "author" },
              body = body,
              created_at = "2023-10-28T18:27:34.082Z",
              position = vim.NIL,
              resolvable = false,
              resolved = false,
            },
          },
        }
      end
      state.DISCUSSION_DATA = {
        discussions = { make_discussion("disc-a", 101, "Discussion A"), make_discussion("disc-b", 102, "Discussion B") },
        unlinked_discussions = {},
        emojis = {},
      }

      vim.cmd("tabnew")
      local tab_a = vim.api.nvim_get_current_tabpage()
      discussions.open()
      local entry_a = windows.get(tab_a)

      vim.cmd("tabnew")
      local tab_b = vim.api.nvim_get_current_tabpage()
      discussions.open()
      local entry_b = windows.get(tab_b)

      local _, line_a = discussions.discussion_tree:get_node("-disc-a")
      local _, line_b = discussions.discussion_tree:get_node("-disc-b")

      vim.api.nvim_set_current_win(entry_a.winid)
      vim.api.nvim_win_set_cursor(entry_a.winid, { line_a, 0 })
      vim.api.nvim_set_current_win(entry_b.winid) -- WinLeave on entry_a's window captures its own node
      vim.api.nvim_win_set_cursor(entry_b.winid, { line_b, 0 })
      vim.api.nvim_set_current_win(entry_a.winid) -- WinLeave on entry_b's window captures its own node

      discussions.rebuild_discussion_tree()

      local _, restored_line_a = discussions.discussion_tree:get_node("-disc-a")
      local _, restored_line_b = discussions.discussion_tree:get_node("-disc-b")

      assert.are.equal(restored_line_a, vim.api.nvim_win_get_cursor(entry_a.winid)[1])
      assert.are.equal(restored_line_b, vim.api.nvim_win_get_cursor(entry_b.winid)[1])
    end)
  end)
end)
