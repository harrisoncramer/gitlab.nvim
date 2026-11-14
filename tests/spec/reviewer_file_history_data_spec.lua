-- Tests for reviewer.get_reviewer_data("file_history"): the commit browser's commit, parent
-- and file are read from the live FileHistory view, which is stubbed here.

local reviewer = require("gitlab.reviewer")
local diffview_lib = require("diffview.lib")
local GitRev = require("diffview.vcs.adapters.git.rev").GitRev

describe("reviewer.get_reviewer_data in file_history mode", function()
  local old_bufnr, new_bufnr, old_win, new_win, parent_sha
  local original_get_current_view = diffview_lib.get_current_view
  local original_history_tabid = reviewer.history_tabid

  ---@param file table The panel's current file entry
  local function stub_view(file)
    diffview_lib.get_current_view = function()
      return {
        panel = { cur_item = { { commit = { hash = "commitABC" } }, file } },
        cur_layout = {
          a = { file = { bufnr = old_bufnr, rev = { commit = parent_sha } } },
          b = { file = { bufnr = new_bufnr, rev = { commit = "commitABC" } } },
        },
      }
    end
  end

  before_each(function()
    old_bufnr = vim.api.nvim_create_buf(false, true)
    new_bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(old_bufnr, 0, -1, false, { "1", "2", "3" })
    vim.api.nvim_buf_set_lines(new_bufnr, 0, -1, false, { "1", "2", "3", "4" })
    vim.cmd("vsplit")
    old_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(old_win, old_bufnr)
    vim.cmd("wincmd l")
    new_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(new_win, new_bufnr)
    parent_sha = "parentXYZ"
    reviewer.history_tabid = vim.api.nvim_get_current_tabpage()
    stub_view({ path = "f.lua" })
  end)

  after_each(function()
    diffview_lib.get_current_view = original_get_current_view
    reviewer.history_tabid = original_history_tabid
    vim.cmd("only")
    vim.api.nvim_buf_delete(old_bufnr, { force = true })
    vim.api.nvim_buf_delete(new_bufnr, { force = true })
  end)

  it("Reads the browsed commit, its parent and the file from the view", function()
    vim.api.nvim_set_current_win(new_win)
    vim.api.nvim_win_set_cursor(new_win, { 4, 0 })

    local data = reviewer.get_reviewer_data("file_history")

    assert.are.same({
      file_name = "f.lua",
      old_file_name = "f.lua",
      old_sha = "parentXYZ",
      new_sha = "commitABC",
      start_line = 4,
      end_line = 4,
      new_file_focused = true,
    }, data)
  end)

  it("Reads the old side and the old path of a renamed file", function()
    stub_view({ path = "g.lua", oldpath = "f.lua" })
    vim.api.nvim_set_current_win(old_win)
    vim.api.nvim_win_set_cursor(old_win, { 2, 0 })

    local data = reviewer.get_reviewer_data("file_history")

    assert.is_not_nil(data)
    assert.are.equal("g.lua", data.file_name)
    assert.are.equal("f.lua", data.old_file_name)
    assert.are.equal(2, data.start_line)
    assert.is_false(data.new_file_focused)
  end)

  it("Refuses outside the commit browser", function()
    reviewer.history_tabid = nil

    assert.is_nil(reviewer.get_reviewer_data("file_history"))
  end)

  it("Refuses when the cursor is not in a diff window", function()
    local other_bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(new_win, other_bufnr)

    assert.is_nil(reviewer.get_reviewer_data("file_history"))

    vim.api.nvim_win_set_buf(new_win, new_bufnr)
    vim.api.nvim_buf_delete(other_bufnr, { force = true })
  end)

  it("Refuses a root commit, which Diffview shows against the empty tree", function()
    parent_sha = GitRev.NULL_TREE_SHA
    vim.api.nvim_set_current_win(new_win)

    assert.is_nil(reviewer.get_reviewer_data("file_history"))
  end)
end)
