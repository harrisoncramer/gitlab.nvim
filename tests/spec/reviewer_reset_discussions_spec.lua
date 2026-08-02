-- Discussion windows can be registered in tabs other than the one being freshly reviewed
-- (e.g. a commit browser left open from a previous MR), so auto-opening discussions for a
-- (re-)opened review must tear all of them down, not just the current tab's.

describe("reviewer.reset_discussions_for_auto_open", function()
  local reviewer = require("gitlab.reviewer")
  local windows = require("gitlab.actions.discussions.windows")
  local gitlab = require("gitlab")
  local original_toggle_discussions

  before_each(function()
    original_toggle_discussions = gitlab.toggle_discussions
    -- Only the window teardown is under test here; toggle_discussions fetches from the Go
    -- server to reopen, which these tests aren't exercising and have no server to talk to.
    gitlab.toggle_discussions = function() end
  end)

  after_each(function()
    gitlab.toggle_discussions = original_toggle_discussions
    vim.cmd("silent! tabonly")
  end)

  it("Closes a discussion window left registered in another tab", function()
    vim.cmd("tabnew")
    local other_tab = vim.api.nvim_get_current_tabpage()
    local split = require("nui.split")({ relative = "editor", position = "right", size = "20%" })
    split:mount()
    windows.set(
      other_tab,
      { split = split, winid = split.winid, bufnr = vim.api.nvim_get_current_buf(), view_type = "discussions" }
    )

    vim.cmd("tabnew") -- the reviewer's own, freshly-opened tab

    reviewer.reset_discussions_for_auto_open()

    assert.is_nil(windows.get(other_tab))
  end)
end)
