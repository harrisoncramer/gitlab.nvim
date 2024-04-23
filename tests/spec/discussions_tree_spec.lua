---@class ResultNodeTree
---@field type string
---@field text string
---@field children ResultNodeTree[]?

---Transform nui nodes to table for easier comparison in tests We could compare directly
---NuiTree.Node but that have a lot of parameters which we don't care about
---@param nodes NuiTree.Node[]
---@param allowed_node_types table<string, boolean>
---@return ResultNodeTree
local function tree_nodes_to_table(nodes, allowed_node_types)
  local result = {}
  for _, node in ipairs(nodes) do
    assert._is_true(allowed_node_types[node.type])
    local current = {
      type = node.type,
      text = node.text,
      children = tree_nodes_to_table(node.__children, allowed_node_types),
    }
    table.insert(result, current)
  end
  return result
end

math.randomseed(os.time())
---Create new discussion node, change ids and path
---@param discussion Discussion
---@param path string
local function copy_discussion_with_new_path(discussion, path)
  local new_discussion = vim.fn.deepcopy(discussion)
  new_discussion.id = tostring(math.random(1000, 10000000))
  new_discussion.notes[1].id = math.random(1000, 10000000)
  new_discussion.notes[1].position.new_path = path
  new_discussion.notes[1].position.old_path = path
  return new_discussion
end

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
    local all_node_types = { note = true, note_body = true, path = true, file_name = true }

    it("Returns empty list with no discussions", function()
      assert.are.same(tree.add_discussions_to_table({}), {})
    end)

    after_each(function()
      utils.time_since = original_time_since
      state.INFO = nil
    end)
    before_each(function()
      state.INFO = {
        web_url = "https://gitlab.com/some-org/-/merge_requests/4963",
      }
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

      discussions = {
        {
          id = "17c7b7558925d0caa7f73684482x9055977bf454",
          individual_note = false,
          notes = {
            {
              attachment = "",
              author = author,
              body = "Multiline comment",
              commit_id = "",
              created_at = "2023-10-28T18:27:34.082Z",
              expires_at = vim.NIL,
              file_name = "",
              id = 1624411,
              noteable_id = 240727,
              noteable_iid = 1,
              noteable_type = "MergeRequest",
              position = {
                base_sha = "d687b5ad4ad5ccd5ae9517efcd103629af1750d6",
                head_sha = "18f76ebeb6e8fcd76a80dce5b592a4f133d2ad05",
                line_range = {
                  ["end"] = {
                    line_code = "8ec9a01bfd10b3191ac6b22252dba2aa95a0579d_18_17",
                    new_line = 0,
                    old_line = 0,
                    type = "new",
                  },
                  start = {
                    line_code = "8ec9a01bfd10b3191ac6b22252dba2aa95a0579d_18_19",
                    new_line = 0,
                    old_line = 0,
                    type = "new",
                  },
                },
                new_line = 17,
                new_path = "README.md",
                old_path = "README.md",
                position_type = "text",
                start_sha = "d687b5ad4ad5ccd5ae9517efcd103629af1750d6",
              },
              resolvable = true,
              resolved = false,
              resolved_at = vim.NIL,
              resolved_by = empty_resolved_by,
              system = false,
              title = "",
              type = "DiffNote",
              updated_at = "2023-10-28T18:27:34.082Z",
            },
          },
        },
        {
          id = "c418928237e9e542b676d25c4211160agcs11733",
          individual_note = false,
          notes = {
            {
              attachment = "",
              author = author,
              body = "test single line comment!",
              commit_id = "",
              created_at = "2023-10-28T18:26:22.336Z",
              expires_at = vim.NIL,
              file_name = "",
              id = 1624415,
              noteable_id = 240727,
              noteable_iid = 1,
              noteable_type = "MergeRequest",
              position = {
                base_sha = "d687b5ad4ad5ccd5ae9517efcd103629af1750d6",
                head_sha = "18f76ebeb6e8fcd76a80dce5b592a4f133d2ad05",
                new_line = 11,
                new_path = "folder_1/folder_2/folder_3/file.lua",
                old_path = "folder_1/folder_2/folder_3/file.lua",
                position_type = "text",
                start_sha = "d687b5ad4ad5ccd5ae9517efcd103629af1750d6",
              },
              resolvable = true,
              resolved = false,
              resolved_at = vim.NIL,
              resolved_by = empty_resolved_by,
              system = false,
              title = "",
              type = "DiffNote",
              updated_at = "2023-10-28T18:26:22.336Z",
            },
          },
        },
      }
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
              created_at = "2021-05-20T10:10:00.648Z",
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
              created_at = "2022-10-25T12:20:30.648Z",
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
      local nodes = tree.add_discussions_to_table(discussions)
      assert.are.same(tree_nodes_to_table(nodes, { note = true, note_body = true }), {
        {
          text = "@gitlab.username 5 days ago -",
          type = "note",
          children = {
            {
              children = {},
              text = "Multiline comment",
              type = "note_body",
            },
          },
        },
        {
          text = "@gitlab.username 5 days ago -",
          type = "note",
          children = {
            {
              text = "test single line comment!",
              type = "note_body",
              children = {},
            },
          },
        },
      })
    end)

    it("Returns path tree of note nodes if tree_type is `by_file_name`", function()
      state.settings.discussion_tree.tree_type = "by_file_name"
      local nodes = tree.add_discussions_to_table(discussions)
      assert.are.same(tree_nodes_to_table(nodes, all_node_types), {
        {
          text = "folder_1/folder_2/folder_3",
          type = "path",
          children = {
            {
              text = "file.lua",
              type = "file_name",
              children = {
                {
                  text = "@gitlab.username 5 days ago -",
                  type = "note",
                  children = {
                    {
                      text = "test single line comment!",
                      type = "note_body",
                      children = {},
                    },
                  },
                },
              },
            },
          },
        },
        {
          text = "README.md",
          type = "file_name",
          children = {
            {
              text = "@gitlab.username 5 days ago -",
              type = "note",
              children = {
                {
                  text = "Multiline comment",
                  type = "note_body",
                  children = {},
                },
              },
            },
          },
        },
      })
    end)
    it("Merges the paths in path tree if there is no file in folder", function()
      state.settings.discussion_tree.tree_type = "by_file_name"
      local nodes = tree.add_discussions_to_table({ discussions[2] })
      assert.are.same(tree_nodes_to_table(nodes, all_node_types), {
        {
          text = "folder_1/folder_2/folder_3",
          type = "path",
          children = {
            {
              text = "file.lua",
              type = "file_name",
              children = {
                {
                  text = "@gitlab.username 5 days ago -",
                  type = "note",
                  children = {
                    {
                      text = "test single line comment!",
                      type = "note_body",
                      children = {},
                    },
                  },
                },
              },
            },
          },
        },
      })
    end)
    it("Correctly places files in folders in file tree", function()
      state.settings.discussion_tree.tree_type = "by_file_name"
      local discussion1 = copy_discussion_with_new_path(discussions[2], "folder_1/first_level.txt")
      local discussion2 = copy_discussion_with_new_path(discussions[2], "folder_1/folder_2/second_level.txt")
      local expected_result = {
        {
          text = "folder_1",
          type = "path",
          children = {
            {
              text = "folder_2",
              type = "path",
              children = {
                {
                  text = "folder_3",
                  type = "path",
                  children = {
                    {
                      text = "file.lua",
                      type = "file_name",
                      children = {
                        {
                          text = "@gitlab.username 5 days ago -",
                          type = "note",
                          children = {
                            {
                              text = "test single line comment!",
                              type = "note_body",
                              children = {},
                            },
                          },
                        },
                      },
                    },
                  },
                },
                {
                  text = "second_level.txt",
                  type = "file_name",
                  children = {
                    {
                      text = "@gitlab.username 5 days ago -",
                      type = "note",
                      children = {
                        {
                          text = "test single line comment!",
                          type = "note_body",
                          children = {},
                        },
                      },
                    },
                  },
                },
              },
            },
            {
              text = "first_level.txt",
              type = "file_name",
              children = {
                {
                  text = "@gitlab.username 5 days ago -",
                  type = "note",
                  children = {
                    {
                      text = "test single line comment!",
                      type = "note_body",
                      children = {},
                    },
                  },
                },
              },
            },
          },
        },
      }
      -- Make sure that order of nodes does not change result!
      assert.are.same(
        tree_nodes_to_table(tree.add_discussions_to_table({ discussions[2], discussion2, discussion1 }), all_node_types),
        expected_result
      )
      assert.are.same(
        tree_nodes_to_table(tree.add_discussions_to_table({ discussion2, discussions[2], discussion1 }), all_node_types),
        expected_result
      )
      assert.are.same(
        tree_nodes_to_table(tree.add_discussions_to_table({ discussion2, discussion1, discussions[2] }), all_node_types),
        expected_result
      )
      assert.are.same(
        tree_nodes_to_table(tree.add_discussions_to_table({ discussion1, discussion2, discussions[2] }), all_node_types),
        expected_result
      )
    end)
    it("Correctly places files with same filenames and different paths", function()
      state.settings.discussion_tree.tree_type = "by_file_name"
      local discussion1 = copy_discussion_with_new_path(discussions[2], "folder_1/diffent_folder/folder_3/file.lua")
      discussion1.notes[1].body = "path: folder_1/diffent_folder/folder_3/file.lua"
      local discussion2 = copy_discussion_with_new_path(discussions[2], "another/folder_2/folder_3/file.lua")
      discussion2.notes[1].body = "path: another/folder_2/folder_3/file.lua"
      local expected_result = {
        {
          text = "another/folder_2/folder_3",
          type = "path",
          children = {
            {
              text = "file.lua",
              type = "file_name",
              children = {
                {
                  text = "@gitlab.username 5 days ago -",
                  type = "note",
                  children = {
                    {
                      text = "path: another/folder_2/folder_3/file.lua",
                      type = "note_body",
                      children = {},
                    },
                  },
                },
              },
            },
          },
        },
        {
          text = "folder_1",
          type = "path",
          children = {
            {
              text = "diffent_folder/folder_3",
              type = "path",
              children = {
                {
                  text = "file.lua",
                  type = "file_name",
                  children = {
                    {
                      text = "@gitlab.username 5 days ago -",
                      type = "note",
                      children = {
                        {
                          text = "path: folder_1/diffent_folder/folder_3/file.lua",
                          type = "note_body",
                          children = {},
                        },
                      },
                    },
                  },
                },
              },
            },
            {
              text = "folder_2/folder_3",
              type = "path",
              children = {
                {
                  text = "file.lua",
                  type = "file_name",
                  children = {
                    {
                      text = "@gitlab.username 5 days ago -",
                      type = "note",
                      children = {
                        {
                          text = "test single line comment!",
                          type = "note_body",
                          children = {},
                        },
                      },
                    },
                  },
                },
              },
            },
          },
        },
      }
      assert.are.same(
        tree_nodes_to_table(tree.add_discussions_to_table({ discussions[2], discussion2, discussion1 }), all_node_types),
        expected_result
      )
    end)
    it("Correctly places multiple notes in same file", function()
      state.settings.discussion_tree.tree_type = "by_file_name"
      local discussion1 = copy_discussion_with_new_path(discussions[2], "folder_1/folder_2/folder_3/file.lua")
      discussion1.notes[1].body = "This is different note!"
      local expected_result = {
        {
          text = "folder_1/folder_2/folder_3",
          type = "path",
          children = {
            {
              text = "file.lua",
              type = "file_name",
              children = {
                {
                  text = "@gitlab.username 5 days ago -",
                  type = "note",
                  children = {
                    {
                      text = "test single line comment!",
                      type = "note_body",
                      children = {},
                    },
                  },
                },
                {
                  text = "@gitlab.username 5 days ago -",
                  type = "note",
                  children = {
                    {
                      text = "This is different note!",
                      type = "note_body",
                      children = {},
                    },
                  },
                },
              },
            },
          },
        },
      }
      assert.are.same(
        tree_nodes_to_table(tree.add_discussions_to_table({ discussions[2], discussion1 }), all_node_types),
        expected_result
      )
    end)
    it("Correctly places multiple notes in same top level file", function()
      state.settings.discussion_tree.tree_type = "by_file_name"
      local discussion1 = copy_discussion_with_new_path(discussions[1], "README.md")
      discussion1.notes[1].body = "This is different note!"
      local expected_result = {
        {
          text = "README.md",
          type = "file_name",
          children = {
            {
              text = "@gitlab.username 5 days ago -",
              type = "note",
              children = {
                {
                  text = "Multiline comment",
                  type = "note_body",
                  children = {},
                },
              },
            },
            {
              text = "@gitlab.username 5 days ago -",
              type = "note",
              children = {
                {
                  text = "This is different note!",
                  type = "note_body",
                  children = {},
                },
              },
            },
          },
        },
      }
      assert.are.same(
        tree_nodes_to_table(tree.add_discussions_to_table({ discussions[1], discussion1 }), all_node_types),
        expected_result
      )
    end)

    it("Returns list of note nodes for unlinked discussions", function()
      state.settings.discussion_tree.tree_type = "simple"
      local nodes = tree.add_discussions_to_table(unlinked_discussions, true)
      assert.are.same(tree_nodes_to_table(nodes, { note = true, note_body = true }), {
        {
          text = "@gitlab.username 5 days ago -",
          type = "note",
          children = {
            {
              children = {},
              text = "Test just unlinked note",
              type = "note_body",
            },
          },
        },
        {
          text = "@gitlab.username 5 days ago -",
          type = "note",
          children = {
            {
              text = "Other unlinked note",
              type = "note_body",
              children = {},
            },
            {
              text = "@gitlab.username 5 days ago ",
              type = "note",
              children = {
                {
                  children = {},
                  text = "Response to the unlinked note",
                  type = "note_body",
                },
              },
            },
          },
        },
      })
      assert.spy(spy_time_since).was.called_with("2021-05-20T10:10:00.648Z")
      assert.spy(spy_time_since).was.called_with("2022-10-25T12:20:30.648Z")
      assert.spy(spy_time_since).was.called_with("2023-11-18T20:15:49.648Z")
    end)

    it("Returns list of note nodes for unlinked discussions even if tree_type is not `simple`", function()
      state.settings.discussion_tree.tree_type = "by_file_name"
      local nodes = tree.add_discussions_to_table(unlinked_discussions, true)
      assert.are.same(tree_nodes_to_table(nodes, { note = true, note_body = true }), {
        {
          text = "@gitlab.username 5 days ago -",
          type = "note",
          children = {
            {
              children = {},
              text = "Test just unlinked note",
              type = "note_body",
            },
          },
        },
        {
          text = "@gitlab.username 5 days ago -",
          type = "note",
          children = {
            {
              text = "Other unlinked note",
              type = "note_body",
              children = {},
            },
            {
              text = "@gitlab.username 5 days ago ",
              type = "note",
              children = {
                {
                  children = {},
                  text = "Response to the unlinked note",
                  type = "note_body",
                },
              },
            },
          },
        },
      })
    end)
  end)
end)
