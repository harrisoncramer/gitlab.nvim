describe("gitlab/actions/comment.lua", function()
  describe("new_location_from_reviewer", function()
    -- comment.lua captures `reviewer` via a top-level require, so stubbing
    -- gitlab.reviewer only takes effect if comment.lua is required again afterwards.
    local function load_comment()
      package.loaded["gitlab.actions.comment"] = nil
      return require("gitlab.actions.comment")
    end

    after_each(function()
      package.loaded["gitlab.reviewer"] = nil
      package.loaded["gitlab.git"] = nil
      package.loaded["gitlab.actions.comment"] = nil
    end)

    it("returns nil when the reviewer has no data to give", function()
      package.loaded["gitlab.reviewer"] = {
        get_reviewer_data = function()
          return nil
        end,
      }

      local comment = load_comment()
      assert.is_nil(comment.new_location_from_reviewer())
    end)

    it("threads reviewer_data's shas and file names into hunks.get_hunks in the right order", function()
      package.loaded["gitlab.reviewer"] = {
        get_reviewer_data = function()
          return {
            old_file_name = "old_name.txt",
            file_name = "new_name.txt",
            old_sha = "old-sha",
            new_sha = "new-sha",
            start_line = 1,
            end_line = 1,
            new_file_focused = true,
          }
        end,
      }

      local seen_old_sha, seen_new_sha, seen_old_path, seen_new_path
      package.loaded["gitlab.git"] = {
        diff_files = function(old_sha, new_sha, old_path, new_path)
          seen_old_sha, seen_new_sha, seen_old_path, seen_new_path = old_sha, new_sha, old_path, new_path
          return nil, nil
        end,
      }

      local comment = load_comment()
      comment.new_location_from_reviewer()

      assert.are.same("old-sha", seen_old_sha)
      assert.are.same("new-sha", seen_new_sha)
      assert.are.same("old_name.txt", seen_old_path)
      assert.are.same("new_name.txt", seen_new_path)
    end)
  end)
end)
