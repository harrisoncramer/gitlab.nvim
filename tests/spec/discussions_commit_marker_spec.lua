describe("gitlab/actions/discussions/tree.lua commit marker", function()
  local tree = require("gitlab.actions.discussions.tree")
  local state = require("gitlab.state")
  local utils = require("gitlab.utils")
  local original_time_since = utils.time_since

  local author = { username = "gitlab.username" }

  before_each(function()
    state.INFO = { web_url = "https://gitlab.com/some-org/-/merge_requests/4963" }
    state.USER = author
    state.settings.discussion_tree.tree_type = "simple"
    utils.time_since = function()
      return "5 days ago"
    end
  end)

  after_each(function()
    utils.time_since = original_time_since
    state.INFO = nil
    state.USER = nil
  end)

  ---@param id integer
  ---@param body string
  ---@param commit_id string
  ---@return Note
  local function make_note(id, body, commit_id)
    return {
      author = author,
      body = body,
      commit_id = commit_id,
      created_at = "2023-10-28T18:27:34.082Z",
      id = id,
      position = vim.NIL,
      resolvable = true,
      resolved = false,
    }
  end

  it("Shows the commit marker on the discussion root when commit_id is set", function()
    local discussion = {
      id = "disc-1",
      individual_note = false,
      notes = { make_note(1, "root comment", "1a2b3c4d5e6f7890") },
    }
    local nodes = tree.add_discussions_to_table({ discussion })
    assert.are.equal("@gitlab.username 5 days ago 1a2b3c4 -", nodes[1].text)
  end)

  it("Does not show the commit marker when Gitlab sends an empty commit_id", function()
    local discussion = {
      id = "disc-2",
      individual_note = false,
      notes = { make_note(2, "root comment", "") },
    }
    local nodes = tree.add_discussions_to_table({ discussion })
    assert.are.equal("@gitlab.username 5 days ago -", nodes[1].text)
  end)

  it("Does not repeat the commit marker on replies within the same discussion", function()
    local discussion = {
      id = "disc-3",
      individual_note = false,
      notes = {
        make_note(3, "root comment", "1a2b3c4d5e6f7890"),
        make_note(4, "reply", "1a2b3c4d5e6f7890"),
      },
    }
    local nodes = tree.add_discussions_to_table({ discussion })
    assert.are.equal("@gitlab.username 5 days ago 1a2b3c4 -", nodes[1].text)
    assert.are.equal("@gitlab.username 5 days ago ", nodes[1].__children[2].text)
  end)

  it("Shows the commit marker on a draft root when commit_id is set", function()
    local draft_notes = require("gitlab.actions.draft_notes")
    local node = draft_notes.build_root_draft_note({
      id = 5,
      note = "draft comment",
      commit_id = "1a2b3c4d5e6f7890",
      position = vim.NIL,
      discussion_id = "",
    })
    assert.are.equal("@gitlab.username ✎ 1a2b3c4 ", node.text)
  end)

  it("Does not show the commit marker on a draft root without a commit_id", function()
    local draft_notes = require("gitlab.actions.draft_notes")
    local node = draft_notes.build_root_draft_note({
      id = 6,
      note = "draft comment",
      commit_id = "",
      position = vim.NIL,
      discussion_id = "",
    })
    assert.are.equal("@gitlab.username ✎ ", node.text)
  end)
end)
