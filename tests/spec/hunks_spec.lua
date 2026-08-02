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

  describe("get_modification_type", function()
    local state = require("gitlab.state")

    local function stub_diff(diff_text)
      package.loaded["gitlab.git"] = {
        diff_files = function()
          return diff_text, nil
        end,
      }
      package.loaded["gitlab.reviewer"] = {
        get_current_file_oldpath = function()
          return "file.txt"
        end,
        get_current_file_path = function()
          return "file.txt"
        end,
      }
    end

    before_each(function()
      state.INFO = { diff_refs = { base_sha = "base-sha" } }
    end)

    after_each(function()
      state.INFO = nil
      package.loaded["gitlab.git"] = nil
      package.loaded["gitlab.reviewer"] = nil
    end)

    it("does not classify the unmodified context line above a single-line deletion as added", function()
      stub_diff([[
diff --git a/file.txt b/file.txt
index 1111111..2222222 100644
--- a/file.txt
+++ b/file.txt
@@ -5 +4,0 @@
-old content that was removed
]])

      local got = hunks.get_modification_type(4, 4, true)
      assert.are_not.same("added", got)
      assert.are.same("bad_file_unmodified", got)
    end)

    it("keeps classifying the context line above a two-line deletion as bad_file_unmodified", function()
      stub_diff([[
diff --git a/file.txt b/file.txt
index 1111111..2222222 100644
--- a/file.txt
+++ b/file.txt
@@ -5,2 +4,0 @@
-old line 5
-old line 6
]])

      local got = hunks.get_modification_type(4, 4, true)
      assert.are.same("bad_file_unmodified", got)
    end)

    it("treats a deleted line as deleted", function()
      stub_diff([[
diff --git a/file.txt b/file.txt
index 1111111..2222222 100644
--- a/file.txt
+++ b/file.txt
@@ -5 +4,0 @@
-old line 5
]])

      assert.are.same("deleted", hunks.get_modification_type(5, 4, false))
    end)

    it("treats the line below a single-line deletion as unmodified", function()
      stub_diff([[
diff --git a/file.txt b/file.txt
index 1111111..2222222 100644
--- a/file.txt
+++ b/file.txt
@@ -5 +4,0 @@
-old line 5
]])

      assert.are.same("unmodified", hunks.get_modification_type(6, 5, false))
    end)

    it("treats the line below a multi-line deletion as unmodified", function()
      stub_diff([[
diff --git a/file.txt b/file.txt
index 1111111..2222222 100644
--- a/file.txt
+++ b/file.txt
@@ -5,2 +4,0 @@
-old line 5
-old line 6
]])

      assert.are.same("unmodified", hunks.get_modification_type(7, 5, false))
    end)
  end)
end)
