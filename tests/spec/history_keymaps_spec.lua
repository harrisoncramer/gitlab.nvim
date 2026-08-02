-- set_keymaps must register the commit-browser keymaps from the default config without
-- erroring; a key name that no longer exists in the defaults would be nil and throw. The
-- hooks must also reach a buffer that Diffview reuses across commits, which fires only
-- DiffviewDiffBufWinEnter and no second DiffviewDiffBufRead.

local history = require("gitlab.reviewer.history")
local reviewer = require("gitlab.reviewer")
local state = require("gitlab.state")

describe("reviewer/history.lua set_keymaps", function()
  it("Registers the browser keymaps from the default config without error", function()
    local bufnr = vim.api.nvim_create_buf(false, true)

    local ok, err = pcall(history.set_keymaps, bufnr)
    assert.is_true(ok, err)

    local lhs = {}
    for _, map in ipairs(vim.api.nvim_buf_get_keymap(bufnr, "n")) do
      lhs[map.lhs] = true
    end

    local reviewer_keymaps = state.settings.keymaps.reviewer
    assert.is_true(lhs[reviewer_keymaps.create_comment] == true)
    assert.is_true(lhs[state.settings.keymaps.help] == true)

    -- create_comment must also act as an operator (o-pending self-motion) and a visual-mode
    -- action, the same as in the live reviewer, so `cc` and a visual selection both work.
    local o_lhs = {}
    for _, map in ipairs(vim.api.nvim_buf_get_keymap(bufnr, "o")) do
      o_lhs[map.lhs] = true
    end
    assert.is_true(o_lhs[reviewer_keymaps.create_comment] == true)

    local v_lhs = {}
    for _, map in ipairs(vim.api.nvim_buf_get_keymap(bufnr, "v")) do
      v_lhs[map.lhs] = true
    end
    assert.is_true(v_lhs[reviewer_keymaps.create_comment] == true)

    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("Attaches the keymaps to a buffer that is only displayed, never read", function()
    history.setup()
    vim.cmd("tabnew")
    reviewer.history_tabid = vim.api.nvim_get_current_tabpage()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(0, bufnr)

    vim.api.nvim_exec_autocmds("User", { pattern = "DiffviewDiffBufWinEnter" })

    local lhs = {}
    for _, map in ipairs(vim.api.nvim_buf_get_keymap(bufnr, "n")) do
      lhs[map.lhs] = true
    end
    assert.is_true(lhs[state.settings.keymaps.reviewer.create_comment] == true)

    vim.cmd("tabclose")
    reviewer.history_tabid = nil
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("Restores the browser keymaps on a buffer the reviewer tab has remapped", function()
    history.setup()
    local bufnr = vim.api.nvim_create_buf(false, true)
    -- The reviewer and the browser share Diffview's blob buffer for the MR head commit, so
    -- the reviewer's own mapping is what sits here after a visit to its tab.
    vim.keymap.set("n", state.settings.keymaps.reviewer.create_comment, function() end, {
      buffer = bufnr,
      desc = "Reviewer comment",
    })

    local diffview_lib = package.loaded["diffview.lib"]
    package.loaded["diffview.lib"] = {
      get_current_view = function()
        return { cur_layout = { a = { file = { bufnr = bufnr } }, b = { file = { bufnr = bufnr } } } }
      end,
    }
    vim.cmd("tabnew")
    reviewer.history_tabid = vim.api.nvim_get_current_tabpage()

    vim.api.nvim_exec_autocmds("TabEnter", {})

    local desc
    for _, map in ipairs(vim.api.nvim_buf_get_keymap(bufnr, "n")) do
      if map.lhs == state.settings.keymaps.reviewer.create_comment then
        desc = map.desc
      end
    end
    assert.are.equal("Create comment for range of motion (commit browser)", desc)

    package.loaded["diffview.lib"] = diffview_lib
    vim.cmd("tabclose")
    reviewer.history_tabid = nil
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)
end)
