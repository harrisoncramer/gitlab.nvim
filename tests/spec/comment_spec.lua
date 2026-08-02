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

-- Tests for the positioned-comment payload builder in actions/comment.lua. A browse-mode
-- caller anchors via M.location.commit_override, which has to carry the browsed commit's
-- whole diff refs because Gitlab validates commit_id against them; the regular reviewer
-- path leaves it unset and gets the MR revision with no commit_id in the payload.

local comment = require("gitlab.actions.comment")
local state = require("gitlab.state")

describe("actions/comment.lua build_position_data", function()
  before_each(function()
    state.MR_REVISIONS = {
      {
        base_commit_sha = "base123",
        start_commit_sha = "start123",
        head_commit_sha = "head123",
      },
    }
  end)

  local function make_location(commit_override)
    return {
      reviewer_data = { file_name = "f.lua", old_file_name = "" },
      location_data = {
        old_line = nil,
        new_line = 10,
        line_range = {
          start = { new_line = 10, type = "new" },
          ["end"] = { new_line = 10, type = "new" },
        },
      },
      commit_override = commit_override,
    }
  end

  it("Anchors a browse-mode comment to the browsed commit", function()
    comment.location = make_location({
      base_sha = "parentXYZ",
      start_sha = "parentXYZ",
      head_sha = "commitABC",
      commit_id = "commitABC",
    })
    local position_data = comment.build_position_data()
    assert.are.equal("commitABC", position_data.head_commit_sha)
    assert.are.equal("commitABC", position_data.commit_id)
    -- Sending the MR base here is what Gitlab rejects with "commit_id does not match the
    -- diff refs"; the position has to describe the commit's own parent..commit diff.
    assert.are.equal("parentXYZ", position_data.base_commit_sha)
    assert.are.equal("parentXYZ", position_data.start_commit_sha)
  end)

  it("Leaves a regular reviewer comment's payload unchanged, with no commit_id", function()
    comment.location = make_location(nil)
    local position_data = comment.build_position_data()
    assert.are.equal("head123", position_data.head_commit_sha)
    assert.is_nil(position_data.commit_id)
  end)
end)
