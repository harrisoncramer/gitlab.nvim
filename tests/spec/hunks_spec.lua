local hunks = require("gitlab.hunks")

describe("gitlab/hunks.lua", function()
  describe("parse_possible_hunk_headers", function()
    it("treats an omitted old count as 1, keeping an explicit new count", function()
      local got = hunks.parse_possible_hunk_headers("@@ -5 +5,3 @@")
      local want = { old_line = 5, old_range = 1, new_line = 5, new_range = 3 }
      assert.are.same(want, got)
    end)

    it("keeps an explicit old count of 0 as a genuine pure insertion", function()
      local got = hunks.parse_possible_hunk_headers("@@ -5,0 +5,3 @@")
      local want = { old_line = 5, old_range = 0, new_line = 5, new_range = 3 }
      assert.are.same(want, got)
    end)

    it("treats both omitted counts as 1", function()
      local got = hunks.parse_possible_hunk_headers("@@ -5 +5 @@")
      local want = { old_line = 5, old_range = 1, new_line = 5, new_range = 1 }
      assert.are.same(want, got)
    end)

    it("treats an omitted new count as 1, keeping an explicit old count", function()
      local got = hunks.parse_possible_hunk_headers("@@ -5,3 +5 @@")
      local want = { old_line = 5, old_range = 3, new_line = 5, new_range = 1 }
      assert.are.same(want, got)
    end)
  end)

  describe("get_hunks", function()
    local function stub_diff(diff_text)
      package.loaded["gitlab.git"] = {
        diff_files = function()
          return diff_text, nil
        end,
      }
    end

    after_each(function()
      package.loaded["gitlab.git"] = nil
    end)

    it("attaches each hunk's own body lines instead of a flat diff blob", function()
      stub_diff([[
diff --git a/file.txt b/file.txt
index 1111111..2222222 100644
--- a/file.txt
+++ b/file.txt
@@ -2,7 +2,6 @@
 line 2
 line 3
 line 4
-line 5
 line 6
 line 7
 line 8
]])

      local got = hunks.get_hunks("old-sha", "new-sha", "file.txt", "file.txt")
      assert.are.same(1, #got)
      assert.are.same({ old_line = 2, old_range = 7, new_line = 2, new_range = 6 }, {
        old_line = got[1].old_line,
        old_range = got[1].old_range,
        new_line = got[1].new_line,
        new_range = got[1].new_range,
      })
      assert.are.same({ " line 2", " line 3", " line 4", "-line 5", " line 6", " line 7", " line 8" }, got[1].lines)
    end)

    it("splits body lines into separate hunks when the diff has more than one", function()
      stub_diff([[
diff --git a/file.txt b/file.txt
index 1111111..2222222 100644
--- a/file.txt
+++ b/file.txt
@@ -2,4 +2,4 @@
 line 2
-line 3
+line three
 line 4
@@ -40,3 +40,4 @@
 line 40
+line 41
 line 42
]])

      local got = hunks.get_hunks("old-sha", "base-sha", "file.txt", "file.txt")
      assert.are.same(2, #got)
      assert.are.same({ " line 2", "-line 3", "+line three", " line 4" }, got[1].lines)
      assert.are.same({ " line 40", "+line 41", " line 42" }, got[2].lines)
    end)

    it("returns no hunks when there is no diff", function()
      stub_diff(nil)
      local got = hunks.get_hunks("old-sha", "base-sha", "file.txt", "file.txt")
      assert.are.same({}, got)
    end)
  end)

  describe("get_line_position", function()
    it("classifies a deleted line and shifts the unmodified lines that follow it", function()
      local hunk = {
        old_line = 2,
        old_range = 7,
        new_line = 2,
        new_range = 6,
        lines = { " a", " b", " c", "-removed", " d", " e", " f" },
      }

      assert.are.same({ old_line = 5, new_line = 5, type = "old" }, hunks.get_line_position({ hunk }, 5, false))
      assert.are.same({ old_line = 6, new_line = 5, type = "" }, hunks.get_line_position({ hunk }, 6, false))
      assert.are.same({ old_line = 6, new_line = 5, type = "" }, hunks.get_line_position({ hunk }, 5, true))
    end)

    it("classifies an added line and shifts the unmodified lines that follow it", function()
      local hunk = {
        old_line = 2,
        old_range = 6,
        new_line = 2,
        new_range = 7,
        lines = { " a", " b", " c", "+added", " d", " e", " f" },
      }

      assert.are.same({ old_line = 5, new_line = 5, type = "new" }, hunks.get_line_position({ hunk }, 5, true))
      assert.are.same({ old_line = 5, new_line = 6, type = "" }, hunks.get_line_position({ hunk }, 5, false))
    end)

    it("treats a line beyond any hunk's context as expanded, shifted by earlier hunks", function()
      local hunks_list = {
        { old_line = 2, old_range = 2, new_line = 2, new_range = 5, lines = { " a", "+b", "+c", " d", "+e" } },
      }

      -- net change introduced by the hunk: new_range(5) - old_range(2) = +3
      assert.are.same(
        { old_line = 50, new_line = 53, type = "expanded" },
        hunks.get_line_position(hunks_list, 50, false)
      )
      assert.are.same(
        { old_line = 47, new_line = 50, type = "expanded" },
        hunks.get_line_position(hunks_list, 50, true)
      )
    end)

    it("treats a line before any hunk as expanded with no shift", function()
      local hunks_list = {
        { old_line = 20, old_range = 1, new_line = 20, new_range = 0, lines = { "-x" } },
      }

      assert.are.same({ old_line = 5, new_line = 5, type = "expanded" }, hunks.get_line_position(hunks_list, 5, false))
    end)

    it("treats a line between two distant hunks as expanded, shifted only by the earlier one", function()
      local hunks_list = {
        { old_line = 2, old_range = 2, new_line = 2, new_range = 5, lines = { " a", "+b", "+c", " d", "+e" } },
        { old_line = 100, old_range = 5, new_line = 103, new_range = 3, lines = { " a", "-b", "-c", " d", " e" } },
      }

      assert.are.same(
        { old_line = 50, new_line = 53, type = "expanded" },
        hunks.get_line_position(hunks_list, 50, false)
      )
    end)

    it("returns an empty hunk list result as expanded with no shift", function()
      assert.are.same({ old_line = 10, new_line = 10, type = "expanded" }, hunks.get_line_position({}, 10, false))
    end)
  end)
end)
