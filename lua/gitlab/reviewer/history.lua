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
-- memories/gitlab-api-experiments/replay-percommit-context.sh). The old (left window) side
-- stays refused: a line the commit deletes need not exist in the MR base at all, and that
-- case is unmeasured (see create_comment).
--
-- Those commit-anchored notes are marked in the browser and nowhere else, since their
-- lines only mean anything in the commit's own diff (see indicators/common.lua).

local List = require("gitlab.utils.list")
local u = require("gitlab.utils")
local state = require("gitlab.state")
local hunks = require("gitlab.hunks")
local Location = require("gitlab.reviewer.location")
local reviewer = require("gitlab.reviewer")
local async = require("diffview.async")

local M = {}

---Return the first parent of `sha`, or nil when git cannot resolve it (a root commit).
---@param sha string
---@return string?
local function first_parent(sha)
  local out = vim.fn.systemlist({ "git", "rev-parse", "--verify", sha .. "^1" })
  if vim.v.shell_error ~= 0 then
    return nil
  end
  return out[1]
end

---@class BrowseContext
---@field commit_sha string SHA of the commit currently shown
---@field parent_sha string SHA of that commit's first parent, the old side of the shown diff
---@field file string Path of the current file (new version)
---@field old_file string Path of the current file (old version; equals file unless renamed)
---@field new_side boolean True if the cursor is in the new (commit) window, false for old (commit^)
---@field line integer Cursor line number in the focused window

---Gather everything needed from the live FileHistory view and cursor. Notifies and
---returns nil when the view, commit, file, or side cannot be determined.
---@return BrowseContext?
M.get_context = function()
  if reviewer.history_tabid == nil or vim.api.nvim_get_current_tabpage() ~= reviewer.history_tabid then
    u.notify("Not in the commit browser", vim.log.levels.ERROR)
    return nil
  end

  local view = require("diffview.lib").get_current_view()
  if view == nil or view.panel == nil or view.panel.cur_item == nil then
    u.notify("No commit browser view", vim.log.levels.ERROR)
    return nil
  end

  local log_entry = view.panel.cur_item[1]
  local commit_sha = log_entry and log_entry.commit and log_entry.commit.hash
  local cur_file = view.panel.cur_item[2]
  if commit_sha == nil or cur_file == nil then
    u.notify("Could not read commit or file", vim.log.levels.ERROR)
    return nil
  end

  local layout = view.cur_layout
  if layout == nil or layout.a == nil or layout.b == nil then
    u.notify("No diff layout", vim.log.levels.ERROR)
    return nil
  end

  local current_bufnr = vim.api.nvim_win_get_buf(vim.api.nvim_get_current_win())
  if current_bufnr ~= layout.a.file.bufnr and current_bufnr ~= layout.b.file.bufnr then
    u.notify("Put the cursor in a diff window", vim.log.levels.ERROR)
    return nil
  end

  local parent_sha = first_parent(commit_sha)
  if parent_sha == nil then
    u.notify("Could not resolve the parent of the browsed commit", vim.log.levels.ERROR)
    return nil
  end

  return {
    commit_sha = commit_sha,
    parent_sha = parent_sha,
    file = cur_file.path,
    old_file = cur_file.oldpath or cur_file.path,
    new_side = current_bufnr == layout.b.file.bufnr,
    line = vim.api.nvim_win_get_cursor(0)[1],
  }
end

---Return the boundaries of the current visual selection, low line first.
---@return integer
---@return integer
local function visual_selection_boundaries()
  local start_line = vim.fn.line("v")
  local end_line = vim.fn.line(".")
  if start_line > end_line then
    start_line, end_line = end_line, start_line
  end
  return start_line, end_line
end

---Build the Location for [start_line, end_line] against the browsed commit's own diff.
---@param ctx BrowseContext
---@param start_line integer
---@param end_line integer
---@return Location
local function build_location(ctx, start_line, end_line)
  ---@type ReviewerData
  local reviewer_data = {
    file_name = ctx.file,
    old_file_name = ctx.old_file,
    old_sha = ctx.parent_sha,
    new_sha = ctx.commit_sha,
    start_line = start_line,
    end_line = end_line,
    new_file_focused = ctx.new_side,
  }
  local diff_hunks = hunks.get_hunks(ctx.parent_sha, ctx.commit_sha, ctx.old_file, ctx.file)
  return Location.new(reviewer_data, diff_hunks)
end

---Attach the commit_override anchoring the location to ctx's browsed commit (see module
---header) and hand it to the existing comment path.
---@param ctx BrowseContext
---@param location table
local function submit_comment(ctx, location)
  location.commit_override = {
    base_sha = ctx.parent_sha,
    start_sha = ctx.parent_sha,
    head_sha = ctx.commit_sha,
    commit_id = ctx.commit_sha,
  }
  require("gitlab.actions.comment").create_comment_for_location(location)
end

---Comment on the current line while browsing, anchored to the browsed commit.
---The old (commit^) side has no verified anchor and is refused, see the module header.
M.create_comment = function()
  local ctx = M.get_context()
  if ctx == nil then
    return
  end

  if not ctx.new_side then
    u.notify("Comments can only be placed from the new side (right window) while browsing commits", vim.log.levels.WARN)
    return
  end

  submit_comment(ctx, build_location(ctx, ctx.line, ctx.line))
end

---Comment on the range covered by the operator motion or visual selection while browsing.
---Same new-side restriction as M.create_comment.
M.create_multiline_comment = function()
  if not u.check_visual_mode() then
    return
  end

  local ctx = M.get_context()
  if ctx == nil then
    u.press_escape()
    return
  end

  if not ctx.new_side then
    u.press_escape()
    u.notify("Comments can only be placed from the new side (right window) while browsing commits", vim.log.levels.WARN)
    return
  end

  local start_line, end_line = visual_selection_boundaries()
  submit_comment(ctx, build_location(ctx, start_line, end_line))
end

---Show `file_path` at commit `sha` in the FileHistory panel and move the cursor to
---`cursor_line` (clamped to the buffer).
---@param view table The live FileHistory view
---@param sha string Target commit SHA
---@param file_path string Path of the file to show
---@param cursor_line integer Line to place the cursor on
M.select_commit = function(view, sha, file_path, cursor_line)
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
  view.cur_layout.b:focus()
  M.refresh_diagnostics()

  local new_win = u.get_window_id_by_buffer_id(view.cur_layout.b.file.bufnr)
  if new_win ~= nil then
    local line_count = vim.api.nvim_buf_line_count(view.cur_layout.b.file.bufnr)
    vim.api.nvim_win_set_cursor(new_win, { math.max(1, math.min(cursor_line, line_count)), 0 })
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
  local bufnr = layout ~= nil and layout.b ~= nil and layout.b.file ~= nil and layout.b.file.bufnr or nil
  if sha == nil or file == nil or bufnr == nil then
    return
  end

  require("gitlab.indicators.diagnostics").place_commit_diagnostics(bufnr, sha, file.path)
end

---Show the commit that a commit-anchored comment was left on, in the commit browser.
---Opens the browser when it is not up yet; Diffview fills its panel from `git log`
---asynchronously, so there is nothing to select from for a moment after that.
---@param sha string The commit the comment is anchored to
---@param file_path string Path of the commented file
---@param line integer Line of the comment, in that commit's version of the file
M.jump_to_commit = function(sha, file_path, line)
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

  M.select_commit(view, sha, file_path, line)
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
