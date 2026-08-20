-- Tests for reviewer/history.lua create_comment: what the new side anchors to, and that
-- the old side refuses. M.get_context and the comment module are stubbed so these run
-- without a live Diffview/FileHistory view, and gitlab.git is stubbed so the position is
-- built from a diff the test controls.

local history = require("gitlab.reviewer.history")
local comment = require("gitlab.actions.comment")

---Make hunks.get_hunks return the hunks of `diff_text` instead of shelling out to git.
local function stub_diff(diff_text)
  package.loaded["gitlab.git"] = {
    diff_files = function()
      return diff_text, nil
    end,
  }
end

describe("reviewer/history.lua create_comment", function()
  local original_get_context = history.get_context
  local original_create_comment_for_location = comment.create_comment_for_location

  -- The browsed commit adds line 41, so line 42 is unmodified and carries both numbers.
  before_each(function()
    stub_diff([[
diff --git a/f.lua b/f.lua
index 1111111..2222222 100644
--- a/f.lua
+++ b/f.lua
@@ -39,3 +39,4 @@
 line 39
 line 40
+line 41 added by the browsed commit
 line 41
]])
  end)

  after_each(function()
    history.get_context = original_get_context
    comment.create_comment_for_location = original_create_comment_for_location
    package.loaded["gitlab.git"] = nil
  end)

  it("Anchors a new-side comment to the browsed commit", function()
    history.get_context = function()
      return {
        commit_sha = "commitABC",
        parent_sha = "parentXYZ",
        file = "f.lua",
        old_file = "f.lua",
        new_side = true,
        line = 41,
      }
    end

    local captured
    comment.create_comment_for_location = function(location)
      captured = location
    end

    history.create_comment()

    assert.is_not_nil(captured)
    assert.are.equal(41, captured.location_data.new_line)
    assert.is_nil(captured.location_data.old_line)
    assert.are.equal("new", captured.location_data.line_range.start.type)
    assert.are.equal(41, captured.location_data.line_range.start.new_line)
    assert.are.equal(41, captured.location_data.line_range["end"].new_line)
    assert.are.equal("commitABC", captured.commit_override.head_sha)
    assert.are.equal("commitABC", captured.commit_override.commit_id)
    -- Gitlab rejects commit_id unless the position is the commit's own diff refs.
    assert.are.equal("parentXYZ", captured.commit_override.base_sha)
    assert.are.equal("parentXYZ", captured.commit_override.start_sha)
  end)

  it("Sends both line numbers for a line the browsed commit did not change", function()
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

    -- Gitlab rejects an unmodified line whose position claims to be an added one.
    assert.is_not_nil(captured)
    assert.are.equal("", captured.location_data.line_range["end"].type)
    assert.are.equal(41, captured.location_data.old_line)
    assert.are.equal(42, captured.location_data.new_line)
    assert.are.equal(41, captured.location_data.line_range["end"].old_line)
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

  -- The browsed commit adds new-side lines 2 and 4, so a 2-4 range types "new" at both
  -- ends and carries no old_line.
  before_each(function()
    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "1", "2", "3", "4", "5" })
    vim.api.nvim_set_current_buf(bufnr)
    stub_diff([[
diff --git a/f.lua b/f.lua
index 1111111..2222222 100644
--- a/f.lua
+++ b/f.lua
@@ -1,3 +1,5 @@
 line 1
+line 2 added by the browsed commit
 line 2
+line 4 added by the browsed commit
 line 3
]])
  end)

  after_each(function()
    history.get_context = original_get_context
    comment.create_comment_for_location = original_create_comment_for_location
    package.loaded["gitlab.git"] = nil
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
