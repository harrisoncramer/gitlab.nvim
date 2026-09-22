-- reviewer.close is the narrow variant: it must close only the reviewer's own tabpage
-- (and the discussion window registered there), leaving any other tab (e.g. the commit
-- browser) and its discussion window untouched. M.reload relies on that to reopen the
-- same MR without tearing down state that belongs to it.

describe("reviewer.close", function()
  local reviewer = require("gitlab.reviewer")
  local windows = require("gitlab.actions.discussions.windows")
  local Split = require("nui.split")

  after_each(function()
    reviewer.tabid = nil
    vim.cmd("tabnew")
    vim.cmd("silent! tabonly")
  end)

  it("Closes the reviewer tab and unmounts its discussion window, leaving another tab's window standing", function()
    vim.cmd("tabnew")
    local other_tab = vim.api.nvim_get_current_tabpage()
    local other_split = Split({ relative = "editor", position = "right", size = "20%" })
    other_split:mount()
    windows.set(other_tab, { split = other_split, winid = other_split.winid, bufnr = vim.api.nvim_get_current_buf() })

    vim.cmd("tabnew")
    reviewer.tabid = vim.api.nvim_get_current_tabpage()
    local reviewer_split = Split({ relative = "editor", position = "right", size = "20%" })
    reviewer_split:mount()
    windows.set(
      reviewer.tabid,
      { split = reviewer_split, winid = reviewer_split.winid, bufnr = vim.api.nvim_get_current_buf() }
    )
    local reviewer_tab = reviewer.tabid

    reviewer.close()

    assert.is_false(vim.api.nvim_tabpage_is_valid(reviewer_tab))
    assert.is_nil(windows.get(reviewer_tab))
    assert.is_not_nil(windows.get(other_tab))

    windows.remove(other_tab)
  end)

  it("Does nothing when there is no reviewer tabpage", function()
    reviewer.tabid = nil
    assert.has_no.errors(function()
      reviewer.close()
    end)
  end)

  it("Does not error when the reviewer tab is the only tabpage (tabclose can't close it)", function()
    vim.cmd("silent! tabonly")
    reviewer.tabid = vim.api.nvim_get_current_tabpage()
    local split = Split({ relative = "editor", position = "right", size = "20%" })
    split:mount()
    windows.set(reviewer.tabid, { split = split, winid = split.winid, bufnr = vim.api.nvim_get_current_buf() })
    local reviewer_tab = reviewer.tabid

    assert.has_no.errors(function()
      reviewer.close()
    end)

    -- tabclose failed (FIXME, pre-existing), so the tab is still there, but its discussion
    -- window was unmounted regardless.
    assert.is_true(vim.api.nvim_tabpage_is_valid(reviewer_tab))
    assert.is_nil(windows.get(reviewer_tab))
  end)
end)
