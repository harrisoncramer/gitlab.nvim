-- A discussion window can be registered in a tab other than the reviewer's own (e.g. the
-- commit browser), so the winbar timer must only stop once none are left anywhere.

describe("reviewer.on_diffview_closed", function()
  local reviewer = require("gitlab.reviewer")
  local windows = require("gitlab.actions.discussions.windows")
  local winbar = require("gitlab.actions.discussions.winbar")

  after_each(function()
    winbar.cleanup_timer()
    reviewer.tabid = nil
    vim.cmd("silent! tabonly")
  end)

  it("Stops the winbar timer when no discussion window is registered anywhere", function()
    reviewer.tabid = 99
    winbar.start_timer()

    reviewer.on_diffview_closed({ tabpage = 99 })

    assert.is_nil(reviewer.tabid)
    assert.is_nil(winbar.timer)
  end)

  it("Keeps the winbar timer running while a discussion window is still registered in another tab", function()
    vim.cmd("tabnew")
    local other_tab = vim.api.nvim_get_current_tabpage()
    windows.set(other_tab, { winid = vim.api.nvim_get_current_win(), bufnr = vim.api.nvim_get_current_buf() })

    reviewer.tabid = 99
    winbar.start_timer()

    reviewer.on_diffview_closed({ tabpage = 99 })

    assert.is_nil(reviewer.tabid)
    assert.is_not_nil(winbar.timer)

    windows.remove(other_tab)
  end)
end)
