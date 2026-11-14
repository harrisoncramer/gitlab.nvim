-- Commenting while browsing a MR commit-by-commit.
--
-- browse_commits opens Diffview's FileHistory (base..head), which shows each commit's
-- isolated commit^..commit diff. GitLab's comment endpoint honors a position anchored to
-- any commit in the MR and keeps the note MR-scoped, so we comment a new-side (right
-- window) line directly against the browsed commit: no base..head translation, every line
-- is commentable. The position has to be the commit's own diff refs, base_sha and
-- start_sha on its first parent and head_sha on the commit, plus a top-level commit_id;
-- anything else is rejected with "commit_id does not match the diff refs".
--
-- GitLab stores base_sha/start_sha as the MR base whatever we send, and renumbers the
-- position's old_line to match, so the position carries the commit's own line numbers and
-- GitLab does the translation (measured, see
-- memories/gitlab-api-experiments/replay-percommit-context.sh). Both windows are
-- commentable: the side the cursor is in decides how the line is typed.
--
-- Those commit-anchored notes are marked in the browser and nowhere else, since their
-- lines only mean anything in the commit's own diff (see indicators/common.lua). Both sides
-- are marked: a deleted line's number survives in the note's line range, which Gitlab stores
-- unchanged even where it renumbers the top-level old_line to the MR base.

local List = require("gitlab.utils.list")
local u = require("gitlab.utils")
local state = require("gitlab.state")
local hunks = require("gitlab.hunks")
local Location = require("gitlab.reviewer.location")
local reviewer = require("gitlab.reviewer")
local async = require("diffview.async")

local M = {}

---Build the Location for the reviewer data's lines against the browsed commit's own diff.
---@param reviewer_data ReviewerData
---@return Location
local function build_location(reviewer_data)
  local diff_hunks =
    hunks.get_hunks(reviewer_data.old_sha, reviewer_data.new_sha, reviewer_data.old_file_name, reviewer_data.file_name)
  return Location.new(reviewer_data, diff_hunks)
end

---Attach the commit_override anchoring the location to the browsed commit (see module
---header) and hand it to the existing comment path.
---@param reviewer_data ReviewerData
---@param location table
local function submit_comment(reviewer_data, location)
  location.commit_override = {
    base_sha = reviewer_data.old_sha,
    start_sha = reviewer_data.old_sha,
    head_sha = reviewer_data.new_sha,
    commit_id = reviewer_data.new_sha,
  }
  require("gitlab.actions.comment").create_comment_for_location(location)
end

---Comment on the current line while browsing, anchored to the browsed commit.
M.create_comment = function()
  local reviewer_data = reviewer.get_reviewer_data("file_history")
  if reviewer_data == nil then
    return
  end

  submit_comment(reviewer_data, build_location(reviewer_data))
end

---Comment on the range covered by the operator motion or visual selection while browsing.
M.create_multiline_comment = function()
  if not u.check_visual_mode() then
    return
  end

  local reviewer_data = reviewer.get_reviewer_data("file_history")
  if reviewer_data == nil then
    u.press_escape()
    return
  end

  submit_comment(reviewer_data, build_location(reviewer_data))
end

---Show `file_path` at commit `sha` in the FileHistory panel and move the cursor to
---`cursor_line` (clamped to the buffer).
---@param view table The live FileHistory view
---@param sha string Target commit SHA
---@param file_path string Path of the file to show
---@param cursor_line integer Line to place the cursor on
---@param on_old_side? boolean Land in the old (commit^) window instead of the new one
M.select_commit = function(view, sha, file_path, cursor_line, on_old_side)
  local log_entry = List.new(view.panel.entries or {}):find(function(entry)
    return entry.commit ~= nil and entry.commit.hash == sha
  end)
  if log_entry == nil then
    u.notify("Commit not found in the browser", vim.log.levels.ERROR)
    return
  end

  -- Only the file entry matching the file we were on is a valid jump target; a commit
  -- that doesn't touch it (e.g. after a rename) must warn rather than silently opening
  -- an unrelated file with a line number computed for the wrong file.
  local file_entry = List.new(log_entry.files or {}):find(function(f)
    return f.path == file_path or f.oldpath == file_path
  end)
  if file_entry == nil then
    u.notify("Commit does not touch this file", vim.log.levels.WARN)
    return
  end

  async.await(view:set_file(file_entry))
  local target = on_old_side and view.cur_layout.a or view.cur_layout.b
  target:focus()
  M.refresh_diagnostics()

  local win = u.get_window_id_by_buffer_id(target.file.bufnr)
  if win ~= nil then
    local line_count = vim.api.nvim_buf_line_count(target.file.bufnr)
    vim.api.nvim_win_set_cursor(win, { math.max(1, math.min(cursor_line, line_count)), 0 })
  end
end

---Mark the browsed commit's own comments in its diff. The reviewer clears the whole
---diagnostic namespace on every refresh, so this has to run on each entry into the browser,
---not only when the shown commit changes.
M.refresh_diagnostics = function()
  if reviewer.history_tabid == nil or vim.api.nvim_get_current_tabpage() ~= reviewer.history_tabid then
    return
  end

  local view = require("diffview.lib").get_current_view()
  local cur_item = view ~= nil and view.panel ~= nil and view.panel.cur_item or nil
  if cur_item == nil then
    return
  end

  local log_entry, file = cur_item[1], cur_item[2]
  local sha = log_entry ~= nil and log_entry.commit ~= nil and log_entry.commit.hash or nil
  local layout = view.cur_layout
  if sha == nil or file == nil or layout == nil then
    return
  end

  local new_bufnr = layout.b ~= nil and layout.b.file ~= nil and layout.b.file.bufnr or nil
  local old_bufnr = layout.a ~= nil and layout.a.file ~= nil and layout.a.file.bufnr or nil
  local diagnostics = require("gitlab.indicators.diagnostics")
  diagnostics.place_commit_diagnostics(new_bufnr, sha, file.path, false)
  diagnostics.place_commit_diagnostics(old_bufnr, sha, file.oldpath or file.path, true)
end

---Show the commit that a commit-anchored comment was left on, in the commit browser.
---Opens the browser when it is not up yet; Diffview fills its panel from `git log`
---asynchronously, so there is nothing to select from for a moment after that.
---@param sha string The commit the comment is anchored to
---@param file_path string Path of the commented file
---@param line integer Line of the comment, in that commit's version of the file
---@param on_old_side? boolean The comment sits on a line the commit deletes
M.jump_to_commit = function(sha, file_path, line, on_old_side)
  reviewer.browse_commits()
  if reviewer.history_tabid == nil or vim.api.nvim_get_current_tabpage() ~= reviewer.history_tabid then
    u.notify("Could not open the commit browser", vim.log.levels.ERROR)
    return
  end

  local view = require("diffview.lib").get_current_view()
  if view == nil or view.panel == nil then
    u.notify("No commit browser view", vim.log.levels.ERROR)
    return
  end

  -- Diffview's post_open picks an initial file asynchronously, guarded on nothing being
  -- selected yet. Waiting for that pick to land keeps ours last; picking first only wins
  -- the race when their callback happens to run before we set the cursor.
  local loaded = vim.wait(2000, function()
    return view.panel:cur_file() ~= nil
  end, 50)
  if not loaded then
    u.notify("The commit browser is still loading, try again", vim.log.levels.WARN)
    return
  end

  M.select_commit(view, sha, file_path, line, on_old_side)
end

---Attach the browse-mode keymaps to a diff buffer.
---@param bufnr integer
M.set_keymaps = function(bufnr)
  if bufnr == nil or not vim.api.nvim_buf_is_loaded(bufnr) then
    return
  end
  local keymaps = state.settings.keymaps
  if keymaps.disable_all or keymaps.reviewer.disable_all then
    return
  end

  if keymaps.reviewer.create_comment ~= false then
    vim.keymap.set("o", keymaps.reviewer.create_comment, function()
      -- The "V" in "V%d$" forces linewise motion, see `:h o_V`
      vim.api.nvim_cmd({ cmd = "normal", bang = true, args = { string.format("V%d$", vim.v.count1) } }, {})
    end, {
      buffer = bufnr,
      desc = "Create comment for [count] lines (commit browser)",
      nowait = keymaps.reviewer.create_comment_nowait,
    })

    vim.keymap.set("n", keymaps.reviewer.create_comment, function()
      reviewer.operator_count = vim.v.count
      reviewer.execute_operatorfunc("history_create_multiline_comment")
    end, {
      buffer = bufnr,
      desc = "Create comment for range of motion (commit browser)",
      nowait = keymaps.reviewer.create_comment_nowait,
    })

    vim.keymap.set("v", keymaps.reviewer.create_comment, function()
      require("gitlab").history_create_multiline_comment()
    end, {
      buffer = bufnr,
      desc = "Create comment for selected text (commit browser)",
      nowait = keymaps.reviewer.create_comment_nowait,
    })
  end

  if keymaps.reviewer.move_to_discussion_tree ~= false then
    vim.keymap.set("n", keymaps.reviewer.move_to_discussion_tree, function()
      require("gitlab").move_to_discussion_tree_from_diagnostic()
    end, {
      buffer = bufnr,
      desc = "Move to discussion (commit browser)",
      nowait = keymaps.reviewer.move_to_discussion_tree_nowait,
    })
  end

  if keymaps.help then
    vim.keymap.set("n", keymaps.help, function()
      require("gitlab.actions.help").open()
    end, { buffer = bufnr, desc = "Open help popup", nowait = keymaps.help_nowait })
  end
end

---Register the FileHistory hooks, once at plugin setup: attach browse keymaps and the
---commit's comment markers to diff buffers (the browse tab gate keeps these out of the
---regular reviewer), and forget the history tab when its view closes.
---
---Both buffer events are needed. DiffviewDiffBufRead fires once per buffer, and
---FileHistory caches blob buffers by revision and path, so a commit's new side is the
---same buffer as the next commit's old side and is read only once. DiffviewDiffBufWinEnter
---fires every time a diff buffer is displayed, which covers the reused ones; setting the
---keymaps again on an already mapped buffer just overwrites them.
M.setup = function()
  local group = vim.api.nvim_create_augroup("gitlab.diffview.autocommand.history_keymaps", {})
  vim.api.nvim_create_autocmd("User", {
    pattern = { "DiffviewDiffBufRead", "DiffviewDiffBufWinEnter" },
    group = group,
    callback = function(args)
      if reviewer.history_tabid ~= nil and vim.api.nvim_get_current_tabpage() == reviewer.history_tabid then
        M.set_keymaps(args.buf)
        M.refresh_diagnostics()
      end
    end,
  })

  -- The reviewer's right side and the browser's newest commit are the same cached blob
  -- buffer, and the reviewer's WinEnter autocmd maps it for the changeset. Switching back
  -- here loads no file, so no Diffview buffer event fires to restore the browse keymaps.
  vim.api.nvim_create_autocmd("TabEnter", {
    group = group,
    callback = function()
      if reviewer.history_tabid == nil or vim.api.nvim_get_current_tabpage() ~= reviewer.history_tabid then
        return
      end
      local view = require("diffview.lib").get_current_view()
      local layout = view ~= nil and view.cur_layout or nil
      if layout == nil or layout.a == nil or layout.b == nil then
        return
      end
      M.set_keymaps(layout.a.file and layout.a.file.bufnr)
      M.set_keymaps(layout.b.file and layout.b.file.bufnr)
      M.refresh_diagnostics()
    end,
  })

  require("diffview.config").user_emitter:on("view_closed", function(_, args)
    reviewer.clear_history_tab(args.tabpage)
  end)
end

return M
