describe("gitlab/actions/discussions/tree.lua", function()
  it("Loads package", function()
    local utils_ok, _ = pcall(require, "gitlab.actions.discussions.tree")
    assert._is_true(utils_ok)
  end)
  describe("add_discussions_to_table", function()
    local tree = require("gitlab.actions.discussions.tree")
    local state = require("gitlab.state")
    local utils = require("gitlab.utils")
    local original_time_since = utils.time_since
    local discussions
    local unlinked_discussions
    local spy_time_since
    it("Returns empty list with no discussions", function()
      assert.are.same(tree.add_discussions_to_table({}), {})
    end)
    after_each(function()
      utils.time_since = original_time_since
    end)
    before_each(function()
      spy_time_since = spy.new(function()
        return "5 days ago"
      end)
      utils.time_since = spy_time_since
      local author = {
        avatar_url = "https://secure.gravatar.com/avatar/a857c8a11e80d5c9116ad6ac4c0fb98a?s=80&d=identicon",
        email = "",
        id = 12345,
        name = "Gitlab Name",
        state = "active",
        username = "gitlab.username",
        web_url = "https://gitlab.com/gitlab.username",
      }
      local empty_resolved_by = {
        avatar_url = "",
        email = "",
        id = 0,
        name = "",
        state = "",
        username = "",
        web_url = "",
      }

      discussions = {}
      unlinked_discussions = {
        {
          id = "16c5b7558923d0caa7f73684481c9055976bf454",
          individual_note = false,
          notes = {
            {
              attachment = "",
              author = author,
              body = "Test just unlinked note",
              commit_id = "",
              created_at = "2023-11-20T20:15:49.648Z",
              expires_at = vim.NIL,
              file_name = "",
              id = 165260,
              noteable_id = 25024,
              noteable_iid = 1,
              noteable_type = "MergeRequest",
              position = vim.NIL,
              resolvable = true,
              resolved = false,
              resolved_at = vim.NIL,
              resolved_by = empty_resolved_by,
              system = false,
              title = "",
              type = "DiscussionNote",
              updated_at = "2023-11-16T24:15:49.648Z",
            },
          },
        },
        {
          id = "38bbe42a1bb8f2a014c4fd87d87760772f090a3c",
          individual_note = false,
          notes = {
            {
              attachment = "",
              author = author,
              body = "Other unlinked note",
              commit_id = "",
              created_at = "2023-11-16T20:15:49.648Z",
              expires_at = vim.NIL,
              file_name = "",
              id = 165260,
              noteable_id = 25024,
              noteable_iid = 1,
              noteable_type = "MergeRequest",
              position = vim.NIL,
              resolvable = true,
              resolved = false,
              resolved_at = vim.NIL,
              resolved_by = empty_resolved_by,
              system = false,
              title = "",
              type = "DiscussionNote",
              updated_at = "2023-11-16T20:15:49.648Z",
            },
            {
              attachment = "",
              author = author,
              body = "Response to the unlinked note",
              commit_id = "",
              created_at = "2023-11-18T20:15:49.648Z",
              expires_at = vim.NIL,
              file_name = "",
              id = 165260,
              noteable_id = 25024,
              noteable_iid = 1,
              noteable_type = "MergeRequest",
              position = vim.NIL,
              resolvable = true,
              resolved = false,
              resolved_at = vim.NIL,
              resolved_by = empty_resolved_by,
              system = false,
              title = "",
              type = "DiscussionNote",
              updated_at = "2023-11-16T20:15:49.648Z",
            },
          },
        },
      }
    end)
    it("Returns list of note nodes if `tree_type` is `simple`", function()
      state.settings.discussion_tree.tree_type = "simple"
      assert.are.same(tree.add_discussions_to_table(discussions), {})
    end)
    it("Returns path tree of note nodes if tree_type is `simple`", function()
      state.settings.discussion_tree.tree_type = "by_file_name"
      assert.are.same(tree.add_discussions_to_table(discussions), {})
    end)
    it("Returns list of note nodes for unlinked discussions", function()
      state.settings.discussion_tree.tree_type = "simple"
      local nodes = tree.add_discussions_to_table(unlinked_discussions, true)
      assert.are.same(#nodes, 2)
      assert.are.same(nodes[1].id, "16c5b7558923d0caa7f73684481c9055976bf454")
      assert.are.same(nodes[1].type, "note")
      assert.are.same(nodes[1].text, "@gitlab.username 5 days ago ")
      assert.are.same(#nodes[1].__children, 1)
      assert.are.same(nodes[1].__children[1].text, "Test just unlinked note")
      assert.are.same(nodes[1].__children[1].type, "note_body")
      assert.are.same(nodes[2].id, "38bbe42a1bb8f2a014c4fd87d87760772f090a3c")
      assert.are.same(nodes[2].type, "note")
      assert.are.same(nodes[2].text, "@gitlab.username 5 days ago ")
      assert.are.same(#nodes[2].__children, 2)
      assert.are.same(nodes[2].__children[1].text, "Other unlinked note")
      assert.are.same(nodes[2].__children[1].type, "note_body")
      assert.are.same(nodes[2].__children[2].text, "@gitlab.username 5 days ago ")
      assert.are.same(nodes[2].__children[2].type, "note")
      assert.are.same(#nodes[2].__children[2].__children, 1)
      assert.are.same(nodes[2].__children[2].__children[1].text, "Response to the unlinked note")
      assert.are.same(nodes[2].__children[2].__children[1].type, "note_body")
      assert.spy(spy_time_since).was.called_with("2023-11-20T20:15:49.648Z")
      assert.spy(spy_time_since).was.called_with("2023-11-16T20:15:49.648Z")
      assert.spy(spy_time_since).was.called_with("2023-11-18T20:15:49.648Z")
    end)
    it("Returns list of note nodes for unlinked discussions even if tree_type is not `simple`", function()
      state.settings.discussion_tree.tree_type = "by_file_name"
      local nodes = tree.add_discussions_to_table(unlinked_discussions, true)
      assert.are.same(#nodes, 2)
      assert.are.same(nodes[1].id, "16c5b7558923d0caa7f73684481c9055976bf454")
      assert.are.same(nodes[2].id, "38bbe42a1bb8f2a014c4fd87d87760772f090a3c")
    end)
  end)
end)
