local hunks = require("gitlab.hunks")
local Location = require("gitlab.reviewer.location")

describe("gitlab/reviewer/location.lua", function()
  local function hunks_from_diff(diff_text)
    package.loaded["gitlab.git"] = {
      diff_files = function()
        return diff_text, nil
      end,
    }
    local file_hunks = hunks.get_hunks("old-sha", "new-sha", "file.txt", "file.txt")
    package.loaded["gitlab.git"] = nil
    return file_hunks
  end

  local function reviewer_data(overrides)
    return vim.tbl_extend("force", {
      old_file_name = "file.txt",
      file_name = "file.txt",
      old_sha = "old-sha",
      new_sha = "new-sha",
      start_line = 1,
      end_line = 1,
      new_file_focused = true,
    }, overrides or {})
  end

  -- A single-line deletion at old line 5, surrounded by --unified=3 context (old 2-8, new 2-7).
  -- Each context line is labeled "old new" so the expected shift is visible in the fixture itself.
  local DELETION_HUNKS = hunks_from_diff([[
diff --git a/file.txt b/file.txt
index 1111111..2222222 100644
--- a/file.txt
+++ b/file.txt
@@ -2,7 +2,6 @@
 line 2 2
 line 3 3
 line 4 4
-line 5
 line 6 5
 line 7 6
 line 8 7
]])

  -- A single-line insertion after old line 4, surrounded by --unified=3 context (old 2-7, new 2-8).
  -- Each context line is labeled "old new" so the expected shift is visible in the fixture itself.
  local ADDITION_HUNKS = hunks_from_diff([[
diff --git a/file.txt b/file.txt
index 1111111..2222222 100644
--- a/file.txt
+++ b/file.txt
@@ -2,6 +2,7 @@
 line 2 2
 line 3 3
 line 4 4
+line   5
 line 5 6
 line 6 7
 line 7 8
]])

  it("builds a range on unmodified lines with real, matching old/new line numbers", function()
    local location =
      Location.new(reviewer_data({ start_line = 2, end_line = 4, new_file_focused = true }), DELETION_HUNKS)

    assert.are.same({ old_line = 2, new_line = 2, type = "" }, location.location_data.line_range.start)
    assert.are.same({ old_line = 4, new_line = 4, type = "" }, location.location_data.line_range["end"])
    assert.are.same(4, location.location_data.old_line)
    assert.are.same(4, location.location_data.new_line)
  end)

  it("nils out the top-level old_line when the range ends on an added line", function()
    -- new-side selection from unmodified line 2 to the added line (new_line 5)
    local location =
      Location.new(reviewer_data({ start_line = 2, end_line = 5, new_file_focused = true }), ADDITION_HUNKS)

    assert.are.same({ old_line = 2, new_line = 2, type = "" }, location.location_data.line_range.start)
    assert.are.same({ old_line = 5, new_line = 5, type = "new" }, location.location_data.line_range["end"])
    assert.is_nil(location.location_data.old_line)
    assert.are.same(5, location.location_data.new_line)
  end)

  it("nils out the top-level new_line when the range ends on a deleted line", function()
    -- old-side selection from unmodified line 2 to the deleted line (old_line 5)
    local location =
      Location.new(reviewer_data({ start_line = 2, end_line = 5, new_file_focused = false }), DELETION_HUNKS)

    assert.are.same({ old_line = 2, new_line = 2, type = "" }, location.location_data.line_range.start)
    assert.are.same({ old_line = 5, new_line = 5, type = "old" }, location.location_data.line_range["end"])
    assert.are.same(5, location.location_data.old_line)
    assert.is_nil(location.location_data.new_line)
  end)

  it("keeps both top-level line numbers real for an expanded (far-from-any-change) range", function()
    -- Line 500 is nowhere near the hunk (old 2-8 / new 2-7), so it falls outside every
    -- hunk's --unified=3 context and is classified as "expanded", not "".
    local location =
      Location.new(reviewer_data({ start_line = 500, end_line = 500, new_file_focused = false }), DELETION_HUNKS)

    assert.are.same({ old_line = 500, new_line = 499, type = "expanded" }, location.location_data.line_range["end"])
    assert.are.same(500, location.location_data.old_line)
    assert.are.same(499, location.location_data.new_line)
  end)
end)
