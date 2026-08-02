-- Tests for reviewer/history.lua create_comment: what the new side anchors to, and that
-- the old side refuses. M.get_context and the comment module are stubbed so these run
-- without a live Diffview/FileHistory view.

local history = require("gitlab.reviewer.history")
local comment = require("gitlab.actions.comment")

describe("reviewer/history.lua create_comment", function()
  local original_get_context = history.get_context
  local original_create_comment_for_location = comment.create_comment_for_location

  after_each(function()
    history.get_context = original_get_context
    comment.create_comment_for_location = original_create_comment_for_location
  end)

  it("Anchors a new-side comment to the browsed commit", function()
    history.get_context = function()
      return {
        commit_sha = "commitABC",
        parent_sha = "parentXYZ",
        file = "f.lua",
        old_file = "f.lua",
        new_side = true,
        line = 42,
      }
    end

    local captured
    comment.create_comment_for_location = function(location)
      captured = location
    end

    history.create_comment()

    assert.is_not_nil(captured)
    assert.are.equal(42, captured.location_data.new_line)
    assert.is_nil(captured.location_data.old_line)
    assert.are.equal(42, captured.location_data.line_range.start.new_line)
    assert.are.equal(42, captured.location_data.line_range["end"].new_line)
    assert.are.equal("commitABC", captured.commit_override.head_sha)
    assert.are.equal("commitABC", captured.commit_override.commit_id)
    -- Gitlab rejects commit_id unless the position is the commit's own diff refs.
    assert.are.equal("parentXYZ", captured.commit_override.base_sha)
    assert.are.equal("parentXYZ", captured.commit_override.start_sha)
  end)

  it("Refuses to comment on the old side and creates no comment", function()
    history.get_context = function()
      return {
        commit_sha = "commitABC",
        file = "f.lua",
        old_file = "f.lua",
        new_side = false,
        line = 5,
      }
    end

    local called = false
    comment.create_comment_for_location = function()
      called = true
    end

    local u = require("gitlab.utils")
    local original_notify = u.notify
    local notified
    u.notify = function(msg, lvl)
      notified = { msg = msg, lvl = lvl }
    end

    history.create_comment()

    u.notify = original_notify

    assert.is_false(called)
    assert.is_not_nil(notified)
    assert.are.equal(
      "Comments can only be placed from the new side (right window) while browsing commits",
      notified.msg
    )
  end)
end)

describe("reviewer/history.lua create_multiline_comment", function()
  local original_get_context = history.get_context
  local original_create_comment_for_location = comment.create_comment_for_location

  local bufnr

  before_each(function()
    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "1", "2", "3", "4", "5" })
    vim.api.nvim_set_current_buf(bufnr)
  end)

  after_each(function()
    history.get_context = original_get_context
    comment.create_comment_for_location = original_create_comment_for_location
    -- Leave any visual mode the test left behind before tearing down the buffer.
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", false, true, true), "nx", false)
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("Anchors a new-side range comment to the browsed commit", function()
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    vim.cmd("normal! V2j")

    history.get_context = function()
      return {
        commit_sha = "commitABC",
        parent_sha = "parentXYZ",
        file = "f.lua",
        old_file = "f.lua",
        new_side = true,
        line = 2,
      }
    end

    local captured
    comment.create_comment_for_location = function(location)
      captured = location
    end

    history.create_multiline_comment()

    assert.is_not_nil(captured)
    assert.are.equal(2, captured.location_data.line_range.start.new_line)
    assert.are.equal(4, captured.location_data.line_range["end"].new_line)
    assert.are.equal(4, captured.location_data.new_line)
    assert.is_nil(captured.location_data.old_line)
    assert.are.equal("commitABC", captured.commit_override.head_sha)
    assert.are.equal("commitABC", captured.commit_override.commit_id)
    assert.are.equal("parentXYZ", captured.commit_override.base_sha)
    assert.are.equal("parentXYZ", captured.commit_override.start_sha)
  end)

  it("Refuses to comment on the old side for a range and creates no comment", function()
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    vim.cmd("normal! V2j")

    history.get_context = function()
      return {
        commit_sha = "commitABC",
        file = "f.lua",
        old_file = "f.lua",
        new_side = false,
        line = 2,
      }
    end

    local called = false
    comment.create_comment_for_location = function()
      called = true
    end

    local u = require("gitlab.utils")
    local original_notify = u.notify
    local notified
    u.notify = function(msg, lvl)
      notified = { msg = msg, lvl = lvl }
    end

    history.create_multiline_comment()

    u.notify = original_notify

    assert.is_false(called)
    assert.is_not_nil(notified)
    assert.are.equal(
      "Comments can only be placed from the new side (right window) while browsing commits",
      notified.msg
    )
  end)
end)
