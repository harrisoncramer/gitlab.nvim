-- Verifies M.browse_commits focuses an already-open commit browser instead of opening a
-- second one: Diffview does not dedupe FileHistory views, so a second DiffviewFileHistory
-- call would orphan the first tab (see reviewer.clear_history_tab).

local reviewer = require("gitlab.reviewer")

describe("reviewer.browse_commits", function()
  it("Switches to the existing tab instead of opening a new browser", function()
    vim.cmd("tabnew")
    local existing_tabid = vim.api.nvim_get_current_tabpage()
    vim.cmd("tabnew")

    reviewer.history_tabid = existing_tabid
    reviewer.browse_commits()

    assert.are.equal(existing_tabid, vim.api.nvim_get_current_tabpage())

    vim.cmd("silent! tabonly")
    reviewer.history_tabid = nil
  end)
end)
