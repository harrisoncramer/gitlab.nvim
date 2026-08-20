-- Comments anchored to a single commit carry `commit_id` and are positioned in that
-- commit's own diff. They must reach the discussion tree with that anchor, and jumping
-- from the tree must land in the commit browser instead of the MR's changeset.

local tree_utils = require("gitlab.actions.discussions.tree")
local draft_notes = require("gitlab.actions.draft_notes")
local common = require("gitlab.actions.common")
local reviewer = require("gitlab.reviewer")
local history = require("gitlab.reviewer.history")
local state = require("gitlab.state")

---A discussion as Gitlab returns it, reduced to what the tree builder reads.
---@param commit_id string
local function discussion_with_commit_id(commit_id)
  return {
    id = "d1",
    individual_note = false,
    notes = {
      {
        id = 1,
        author = { username = "gitlab.username" },
        body = "Commented while browsing",
        commit_id = commit_id,
        created_at = "2026-08-01T10:00:00.000Z",
        resolvable = true,
        resolved = false,
        position = {
          new_path = "file.lua",
          old_path = "file.lua",
          new_line = 11,
          base_sha = "base",
          start_sha = "base",
          head_sha = commit_id,
        },
      },
    },
  }
end

describe("actions/discussions/tree commit anchor", function()
  before_each(function()
    state.INFO = { web_url = "https://gitlab.example/-/merge_requests/1" }
    state.settings.discussion_tree.tree_type = "simple"
  end)
  after_each(function()
    state.INFO = nil
  end)

  it("Carries commit_id onto the root node", function()
    local nodes = tree_utils.add_discussions_to_table({ discussion_with_commit_id("abc123") })
    assert.are.equal("abc123", nodes[1].commit_id)
  end)

  it("Leaves commit_id nil for the empty string Gitlab sends on plain comments", function()
    local nodes = tree_utils.add_discussions_to_table({ discussion_with_commit_id("") })
    assert.is_nil(nodes[1].commit_id)
  end)
end)

describe("actions/draft_notes.build_root_draft_note commit anchor", function()
  before_each(function()
    state.INFO = { web_url = "https://gitlab.example/-/merge_requests/1" }
    state.USER = { username = "gitlab.username" }
  end)
  after_each(function()
    state.INFO = nil
    state.USER = nil
  end)

  ---A draft note as Gitlab returns it, reduced to what the tree builder reads.
  ---@param commit_id string
  local function draft_note_with_commit_id(commit_id)
    return {
      id = 1,
      note = "Commented while browsing",
      commit_id = commit_id,
      position = vim.NIL,
      discussion_id = "",
    }
  end

  it("Carries commit_id onto the root node", function()
    local node = draft_notes.build_root_draft_note(draft_note_with_commit_id("abc123"))
    assert.are.equal("abc123", node.commit_id)
  end)

  it("Leaves commit_id nil for the empty string Gitlab sends on plain draft comments", function()
    local node = draft_notes.build_root_draft_note(draft_note_with_commit_id(""))
    assert.is_nil(node.commit_id)
  end)
end)

describe("actions/common.jump_to_reviewer", function()
  local originals = {}

  before_each(function()
    originals.get_current_node = common.get_current_node
    originals.get_line_number_from_node = common.get_line_number_from_node
    originals.reviewer_jump = reviewer.jump
    originals.jump_to_commit = history.jump_to_commit
    originals.notify = require("gitlab.utils").notify
  end)

  after_each(function()
    common.get_current_node = originals.get_current_node
    common.get_line_number_from_node = originals.get_line_number_from_node
    reviewer.jump = originals.reviewer_jump
    history.jump_to_commit = originals.jump_to_commit
    require("gitlab.utils").notify = originals.notify
  end)

  ---@param node table The node the cursor is on
  ---@param is_new_sha boolean
  local function arrange(node, is_new_sha)
    local calls = { reviewer = {}, history = {}, notified = {} }
    common.get_current_node = function()
      return node
    end
    common.get_line_number_from_node = function()
      return 11, is_new_sha
    end
    reviewer.jump = function(...)
      table.insert(calls.reviewer, { ... })
    end
    history.jump_to_commit = function(...)
      table.insert(calls.history, { ... })
    end
    require("gitlab.utils").notify = function(msg)
      table.insert(calls.notified, msg)
    end
    return calls
  end

  it("Sends a commit-anchored comment to the commit browser", function()
    local calls = arrange({ is_root = true, type = "note", file_name = "file.lua", commit_id = "abc123" }, true)

    common.jump_to_reviewer({})

    assert.are.same({}, calls.reviewer)
    assert.are.same({ { "abc123", "file.lua", 11, false } }, calls.history)
  end)

  it("Sends a plain comment to the reviewer", function()
    local calls = arrange({ is_root = true, type = "note", file_name = "file.lua", old_file_name = "file.lua" }, true)

    common.jump_to_reviewer({})

    assert.are.same({}, calls.history)
    assert.are.equal(1, #calls.reviewer)
  end)

  it("Takes an old-side commit comment's line from the range, not the renumbered position", function()
    local calls = arrange({
      is_root = true,
      type = "note",
      file_name = "file.lua",
      commit_id = "abc123",
      range = { start = { old_line = 10 }, ["end"] = { old_line = 10 } },
    }, false)

    common.jump_to_reviewer({})

    assert.are.same({}, calls.reviewer)
    -- 11 is what Gitlab renumbered against the MR base; 10 is the browser's own line.
    assert.are.same({ { "abc123", "file.lua", 10, true } }, calls.history)
  end)

  it("Falls back to the stored line for a commit comment with no range", function()
    local calls = arrange({ is_root = true, type = "note", file_name = "file.lua", commit_id = "abc123" }, false)

    common.jump_to_reviewer({})

    assert.are.same({ { "abc123", "file.lua", 11, true } }, calls.history)
  end)
end)
