-- Verifies the tabpage-keyed registry: entries stay independent across tabs, and get pruned
-- once their window or tabpage is no longer live.

local windows = require("gitlab.actions.discussions.windows")

describe("actions/discussions/windows", function()
  after_each(function()
    vim.cmd("silent! tabonly")
  end)

  it("Returns the entry set for the current tabpage", function()
    local winid = vim.api.nvim_get_current_win()
    local tabid = vim.api.nvim_get_current_tabpage()
    local entry = { winid = winid, bufnr = vim.api.nvim_get_current_buf(), view_type = "discussions" }

    windows.set(tabid, entry)

    assert.are.equal(entry, windows.get())
  end)

  it("Keeps two tabpages' entries independent", function()
    local first_tabid = vim.api.nvim_get_current_tabpage()
    local first_entry = { winid = vim.api.nvim_get_current_win(), bufnr = vim.api.nvim_get_current_buf() }
    windows.set(first_tabid, first_entry)

    vim.cmd("tabnew")
    local second_tabid = vim.api.nvim_get_current_tabpage()
    local second_entry = { winid = vim.api.nvim_get_current_win(), bufnr = vim.api.nvim_get_current_buf() }
    windows.set(second_tabid, second_entry)

    assert.are.equal(second_entry, windows.get())
    vim.api.nvim_set_current_tabpage(first_tabid)
    assert.are.equal(first_entry, windows.get())
  end)

  it("Prunes an entry whose window closed, on the next each(), and any() goes false", function()
    vim.cmd("split")
    local winid = vim.api.nvim_get_current_win()
    local tabid = vim.api.nvim_get_current_tabpage()
    windows.set(tabid, { winid = winid, bufnr = vim.api.nvim_get_current_buf() })
    assert.is_true(windows.any())

    vim.api.nvim_win_close(winid, true)

    local seen = {}
    windows.each(function(_, id)
      table.insert(seen, id)
    end)
    assert.are.same({}, seen)
    assert.is_false(windows.any())
  end)

  it("get() returns nil once the entry's window was moved to another tabpage", function()
    vim.cmd("tabnew")
    vim.cmd("split")
    local tabid = vim.api.nvim_get_current_tabpage()
    windows.set(tabid, { winid = vim.api.nvim_get_current_win(), bufnr = vim.api.nvim_get_current_buf() })

    vim.cmd("wincmd T")

    assert.is_nil(windows.get(tabid))
  end)

  it("remove_by_winid removes the entry owning that window and leaves others", function()
    local first_tabid = vim.api.nvim_get_current_tabpage()
    local first_winid = vim.api.nvim_get_current_win()
    windows.set(first_tabid, { winid = first_winid, bufnr = vim.api.nvim_get_current_buf() })

    vim.cmd("tabnew")
    local second_tabid = vim.api.nvim_get_current_tabpage()
    local second_winid = vim.api.nvim_get_current_win()
    windows.set(second_tabid, { winid = second_winid, bufnr = vim.api.nvim_get_current_buf() })

    windows.remove_by_winid(first_winid)

    assert.is_nil(windows.get(first_tabid))
    assert.is_not_nil(windows.get(second_tabid))
  end)

  it("get() returns nil once the entry's tabpage itself is closed", function()
    vim.cmd("tabnew")
    local tabid = vim.api.nvim_get_current_tabpage()
    windows.set(tabid, { winid = vim.api.nvim_get_current_win(), bufnr = vim.api.nvim_get_current_buf() })

    vim.cmd("tabclose")

    assert.is_nil(windows.get(tabid))
  end)
end)
