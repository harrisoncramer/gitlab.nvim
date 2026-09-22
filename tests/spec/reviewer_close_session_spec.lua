-- reviewer.close_session is the teardown variant: on top of the narrow reviewer.close, it
-- must also close the commit-browser tab and forget history_tabid, and unmount any
-- discussion window left registered elsewhere.

describe("reviewer.close_session", function()
  local reviewer = require("gitlab.reviewer")
  local windows = require("gitlab.actions.discussions.windows")
  local Split = require("nui.split")

  after_each(function()
    reviewer.tabid = nil
    reviewer.history_tabid = nil
    vim.cmd("tabnew")
    vim.cmd("silent! tabonly")
  end)

  it(
    "Closes the reviewer tab and the commit-browser tab, clears history_tabid, and unmounts a stray discussion window",
    function()
      vim.cmd("tabnew")
      local stray_tab = vim.api.nvim_get_current_tabpage()
      local stray_split = Split({ relative = "editor", position = "right", size = "20%" })
      stray_split:mount()
      windows.set(stray_tab, { split = stray_split, winid = stray_split.winid, bufnr = vim.api.nvim_get_current_buf() })

      vim.cmd("tabnew")
      reviewer.history_tabid = vim.api.nvim_get_current_tabpage()
      local browser_tab = reviewer.history_tabid

      vim.cmd("tabnew")
      reviewer.tabid = vim.api.nvim_get_current_tabpage()
      local reviewer_split = Split({ relative = "editor", position = "right", size = "20%" })
      reviewer_split:mount()
      windows.set(
        reviewer.tabid,
        { split = reviewer_split, winid = reviewer_split.winid, bufnr = vim.api.nvim_get_current_buf() }
      )
      local reviewer_tab = reviewer.tabid

      reviewer.close_session()

      assert.is_false(vim.api.nvim_tabpage_is_valid(reviewer_tab))
      assert.is_false(vim.api.nvim_tabpage_is_valid(browser_tab))
      assert.is_nil(reviewer.history_tabid)
      assert.is_nil(windows.get(stray_tab))
      -- the stray tab itself is not a browser/reviewer tab, so close_all only unmounts its
      -- window, it doesn't close the tab.
      assert.is_true(vim.api.nvim_tabpage_is_valid(stray_tab))
    end
  )

  it("Leaves history_tabid untouched when there is no commit-browser tab", function()
    reviewer.history_tabid = nil
    reviewer.tabid = nil

    reviewer.close_session()

    assert.is_nil(reviewer.history_tabid)
  end)

  it(
    "Still clears history_tabid and unmounts stray windows when the reviewer tab fails to close (last tabpage)",
    function()
      vim.cmd("silent! tabonly")
      reviewer.tabid = vim.api.nvim_get_current_tabpage()
      reviewer.history_tabid = nil
      local split = Split({ relative = "editor", position = "right", size = "20%" })
      split:mount()
      windows.set(reviewer.tabid, { split = split, winid = split.winid, bufnr = vim.api.nvim_get_current_buf() })

      assert.has_no.errors(function()
        reviewer.close_session()
      end)

      assert.is_nil(windows.get(reviewer.tabid))
    end
  )
end)
