-- This Module contains all of the reviewer code. This is the code
-- that parses or interacts with diffview directly, such as opening
-- and closing, getting metadata about the current view, and registering
-- callbacks for open/close actions.

local List = require("gitlab.utils.list")
local u = require("gitlab.utils")
local state = require("gitlab.state")
local async = require("diffview.async")

local M = {
  is_open = false,
  bufnr = nil,
  tabid = nil,
  history_tabid = nil,
  stored_win = nil,
  buf_winids = {},
}

-- Open the reviewer windows.
M.open = function()
  require("gitlab.emoji").init() -- Read in emojis for lookup purposes
  local diff_refs = state.INFO.diff_refs
  if diff_refs == nil then
    u.notify("Gitlab did not provide diff refs required to review this MR", vim.log.levels.ERROR)
    return
  end

  if diff_refs.base_sha == "" or diff_refs.head_sha == "" then
    u.notify("Merge request contains no changes", vim.log.levels.ERROR)
    return
  end

  require("gitlab.git_async").check_current_branch_up_to_date_on_remote()
  local git = require("gitlab.git")

  -- The rename threshold used by Gitlab (through Gitaly) is 30%, see
  -- https://gitlab.com/gitlab-org/gitaly/-/blob/db39e26f8f8a8da62e2c2db00325cf51315c89db/internal/gitaly/service/diff/commit_diff.go#L64-64
  -- https://gitlab.com/gitlab-org/gitaly/-/blob/0e81e24ae1f650c242670eb7bf66c4b4b91b7813/internal/gitaly/service/diff/find_changed_paths.go#L116-116
  local diffview_open_command = "DiffviewOpen --rename-threshold=30"

  if state.settings.reviewer_settings.diffview.imply_local then
    local has_clean_tree, err = git.has_clean_tree()
    if err ~= nil then
      return
    end
    if has_clean_tree then
      diffview_open_command = diffview_open_command .. " --imply-local"
    else
      u.notify("Working tree unclean. Stash or commit all changes to use 'imply_local'.", vim.log.levels.WARN)
      state.settings.reviewer_settings.diffview.imply_local = false
    end
  end

  M.is_open = true
  vim.api.nvim_command(string.format("%s %s..%s", diffview_open_command, diff_refs.base_sha, diff_refs.head_sha))

  M.diffview = require("diffview.lib").get_current_view() --[[@as DiffView?]]
  if M.diffview == nil then
    u.notify("Could not find Diffview view", vim.log.levels.ERROR)
    return
  end
  M.diffview_layout = M.diffview.cur_layout --[[@as Diff4]]
  M.tabid = vim.api.nvim_get_current_tabpage()

  if state.settings.discussion_diagnostic ~= nil or state.settings.discussion_sign ~= nil then
    u.notify(
      "Diagnostics are now configured as settings.discussion_signs, see :h gitlab.nvim.signs-and-diagnostics",
      vim.log.levels.WARN
    )
  end

  -- Register Diffview hook for close event to set tab page # to nil
  local on_diffview_closed = function(view)
    if view.tabpage == M.tabid then
      M.tabid = nil
      require("gitlab.actions.discussions.winbar").cleanup_timer()
    end
  end
  require("diffview.config").user_emitter:on("view_closed", function(_, args)
    if M.tabid == args.tabpage then
      M.is_open = false
      on_diffview_closed(args)
    end
  end)

  if state.settings.discussion_tree.auto_open then
    local discussions = require("gitlab.actions.discussions")
    discussions.close()
    require("gitlab").toggle_discussions() -- Fetches data and opens discussions
  end

  git.check_mr_in_good_condition()
end

-- Opens a commit-by-commit browser for the MR range using Diffview's FileHistory. Each
-- entry shows a single commit's isolated diff, for understanding how the MR was built up
-- and commenting against the browsed commit directly (see reviewer/history.lua).
M.browse_commits = function()
  -- Diffview does not deduplicate views: DiffviewFileHistory always opens a new tabpage.
  -- Focus the existing browser instead of stacking a second, orphaning the first (whose
  -- keymaps would then reject every action, since only the newest tab passes the gate).
  if M.history_tabid ~= nil and vim.api.nvim_tabpage_is_valid(M.history_tabid) then
    vim.api.nvim_set_current_tabpage(M.history_tabid)
    return
  end

  local diff_refs = state.INFO.diff_refs
  if diff_refs == nil then
    u.notify("Gitlab did not provide diff refs required to browse this MR", vim.log.levels.ERROR)
    return
  end

  if diff_refs.base_sha == "" or diff_refs.head_sha == "" then
    u.notify("Merge request contains no changes", vim.log.levels.ERROR)
    return
  end

  vim.api.nvim_command(string.format("DiffviewFileHistory --range=%s..%s", diff_refs.base_sha, diff_refs.head_sha))
  M.history_tabid = vim.api.nvim_get_current_tabpage()
end

---Forget the commit-history tab once its Diffview view closes. history_tabid gates the
---browse keymaps and comment path; left pointing at a closed tab it would be a dangling
---handle. Mirrors the tabid cleanup in M.open.
---@param tabpage integer Tabpage of the closed Diffview view
M.clear_history_tab = function(tabpage)
  if M.history_tabid == tabpage then
    M.history_tabid = nil
  end
end

---Close the reviewer and clean up.
M.close = function()
  if M.tabid ~= nil and vim.api.nvim_tabpage_is_valid(M.tabid) then
    -- FIXME: This fails if there is only one tabpage. Find a way to use DiffviewClose
    -- that was originally here, but use it for the correct tabpage when there are
    -- multiple Diffviews open.
    vim.cmd.tabclose(vim.api.nvim_tabpage_get_number(M.tabid))
  end
  local discussions = require("gitlab.actions.discussions")
  discussions.close()
end

---Load new INFO state from Gitlab. Then, if diffview.api is available, apply the new
---diff refs to the existing diffview, otherwise close and re-open the reviewer.
M.reload = function()
  state.load_new_state("info", function()
    state.load_new_state("revisions", function()
      local has_api, api = pcall(require, "diffview.api")
      if has_api then
        api.set_revs(
          string.format("%s..%s", state.INFO.diff_refs.base_sha, state.INFO.diff_refs.head_sha),
          { view = M.diffview }
        )
      else
        M.close()
        M.open()
      end
    end)
  end)
end

---Jump to the location provided in the reviewer window.
---@param file_name string The file name after change
---@param old_file_name string The file name before change (different from file_name for renamed/moved files)
---@param linenr integer Line number from the discussion node
---@param new_buffer boolean If true, jump to the NEW SHA
M.jump = function(file_name, old_file_name, linenr, new_buffer)
  -- Draft comments don't have `old_file_name` set
  old_file_name = old_file_name or file_name

  if M.tabid == nil then
    u.notify("Can't jump to Diffvew. Is it open?", vim.log.levels.ERROR)
    return
  end
  vim.api.nvim_set_current_tabpage(M.tabid)

  if M.diffview == nil then
    u.notify("Could not find Diffview view", vim.log.levels.ERROR)
    return
  end

  local files = M.diffview.panel:ordered_file_list()
  local file = List.new(files):find(function(f)
    local oldpath = f.oldpath ~= nil and f.oldpath or f.path
    return new_buffer and f.path == file_name or oldpath == old_file_name
  end)
  if file == nil then
    u.notify(
      string.format("The file %s for which the comment was made doesn't exist in HEAD.", file_name),
      vim.log.levels.WARN
    )
    return
  end
  async.await(M.diffview:set_file(file))

  local number_of_lines
  if new_buffer then
    M.diffview_layout.b:focus()
    number_of_lines = u.get_buffer_length(M.diffview_layout.b.file.bufnr)
  else
    M.diffview_layout.a:focus()
    number_of_lines = u.get_buffer_length(M.diffview_layout.a.file.bufnr)
  end
  if linenr > number_of_lines then
    u.notify("Diagnostic position outside buffer. Jumping to last line instead.", vim.log.levels.WARN)
    linenr = number_of_lines
  end
  vim.api.nvim_win_set_cursor(0, { linenr, 0 })
  u.open_fold_under_cursor()
  vim.cmd("normal! zz")
end

---Return start line and end line of visual selection.
---@return integer
---@return integer
local get_visual_selection_boundaries = function()
  local start_line = vim.fn.line("v")
  local end_line = vim.fn.line(".")
  if start_line > end_line then
    start_line, end_line = end_line, start_line
  end
  return start_line, end_line
end

---Get the data from the reviewer: file names, line information, and cursor focus.
---@return ReviewerData?
M.get_reviewer_data = function()
  if M.diffview_layout == nil then
    return
  end

  local start_line, end_line = get_visual_selection_boundaries()
  local new_file_focused = M.is_new_file_focused(vim.api.nvim_get_current_win())
  local diff_refs = state.INFO.diff_refs

  return {
    old_file_name = M.is_file_renamed() and M.diffview_layout.a.file.path or M.diffview_layout.b.file.path,
    file_name = M.diffview_layout.b.file.path,
    old_sha = diff_refs.base_sha,
    new_sha = diff_refs.head_sha,
    start_line = start_line,
    end_line = end_line,
    new_file_focused = new_file_focused,
  }
end

---Return true if user is focused on the new version of the file, otherwise false.
---@param current_win integer The ID of the currently focused window
---@return boolean
M.is_new_file_focused = function(current_win)
  local b_win = u.get_window_id_by_buffer_id(M.diffview_layout.b.file.bufnr)
  local a_win = u.get_window_id_by_buffer_id(M.diffview_layout.a.file.bufnr)
  if a_win ~= current_win and b_win ~= current_win then
    current_win = M.stored_win
    M.stored_win = nil
  end
  return current_win == b_win
end

---Get data of currently shown file.
---@return FileEntry?
M.get_current_file_data = function()
  return M.diffview and M.diffview.panel and M.diffview.panel.cur_file
end

---Get path of currently shown file.
---@return string?
M.get_current_file_path = function()
  local file_data = M.get_current_file_data()
  return file_data and file_data.path
end

---Get old path of currently shown file.
---@return string?
M.get_current_file_oldpath = function()
  local file_data = M.get_current_file_data()
  return file_data and (file_data.oldpath or file_data.path)
end

---Return true if current file is renamed, otherwise false.
---@return boolean?
M.is_file_renamed = function()
  local file_data = M.get_current_file_data()
  return file_data and file_data.status == "R"
end

---Return true if current file has changes, otherwise false.
---@return boolean?
M.does_file_have_changes = function()
  local file_data = M.get_current_file_data()
  return file_data and (file_data.stats.additions > 0 or file_data.stats.deletions > 0)
end

---Run callback every time the buffer in one of the two reviewer windows changes.
---@param callback fun(opts: table) For more information about opts see `callback` in :h nvim_create_autocmd
M.set_callback_for_file_changed = function(callback)
  local group = vim.api.nvim_create_augroup("gitlab.diffview.autocommand.file_changed", {})
  vim.api.nvim_create_autocmd("User", {
    pattern = { "DiffviewDiffBufWinEnter" },
    group = group,
    callback = function(...)
      if M.tabid == vim.api.nvim_get_current_tabpage() then
        callback(...)
      end
    end,
  })
end

---Run callback the first time a new diff buffer is created and loaded into a window.
---@param callback fun(opts: table) For more information about opts see `callback` in :h nvim_create_autocmd
M.set_callback_for_buf_read = function(callback)
  local group = vim.api.nvim_create_augroup("gitlab.diffview.autocommand.buf_read", {})
  vim.api.nvim_create_autocmd("User", {
    pattern = { "DiffviewDiffBufRead" },
    group = group,
    callback = function(...)
      -- Only run the callback when we're in the MR's tabpage or when the tabpage has
      -- not yet been set (tabid = nil) in a freshly started review (is_open = true).
      -- FIXME: This is a hacky workaround for cases when an added file is diffed
      -- against diffview://null and this autocommand fires before tabid is set.
      if vim.api.nvim_get_current_tabpage() == M.tabid or (M.is_open and M.tabid == nil) then
        callback(...)
      end
    end,
  })
end

---Run callback when the reviewer is closed or the user switches to another tab.
---@param callback fun(opts: table) For more information about opts see `callback` in :h nvim_create_autocmd
M.set_callback_for_reviewer_leave = function(callback)
  local group = vim.api.nvim_create_augroup("gitlab.diffview.autocommand.leave", {})
  vim.api.nvim_create_autocmd("User", {
    pattern = { "DiffviewViewLeave", "DiffviewViewClosed" },
    group = group,
    callback = function(...)
      if vim.api.nvim_get_current_tabpage() == M.tabid then
        callback(...)
      end
    end,
  })
end

---Run callback when the reviewer is opened for the first time or the view is entered
---from another tab page.
---@param callback fun(opts: table) For more information about opts see `callback` in :h nvim_create_autocmd
M.set_callback_for_reviewer_enter = function(callback)
  local group = vim.api.nvim_create_augroup("gitlab.diffview.autocommand.enter", {})
  vim.api.nvim_create_autocmd("User", {
    pattern = { "DiffviewViewEnter", "DiffviewViewOpened" },
    group = group,
    callback = function(...)
      if vim.api.nvim_get_current_tabpage() == M.tabid then
        callback(...)
      end
    end,
  })
end

-- TODO: Add callback for view_post_layout to update M.diffview and M.diffview_layout
-- after switching layout.

---Create the line-wise visual selection in the range of the motion (or on the [count]
---number of lines) and execute the callback. After that, restore the cursor position
---and the original operatorfunc.
---@param cb string Name of the gitlab.nvim API function to call
M.execute_callback = function(cb)
  return function()
    vim.api.nvim_cmd({ cmd = "normal", bang = true, args = { "'[V']" } }, {})
    local _, err = pcall(
      vim.api.nvim_cmd,
      { cmd = "lua", args = { ("require'gitlab'.%s()"):format(cb) }, mods = { lockmarks = true } },
      {}
    )
    vim.api.nvim_win_set_cursor(M.old_winnr, M.old_cursor_position)
    vim.opt.operatorfunc = M.old_opfunc
    if err ~= "" then
      u.notify_vim_error(err, vim.log.levels.ERROR)
    end
  end
end

---Set the operatorfunc that will work on the lines defined by the motion that follows
---after the operator mapping, and enter the operator-pending mode.
---@param cb string Name of the gitlab.nvim API function to call, e.g., "create_multiline_comment"
M.execute_operatorfunc = function(cb)
  M.old_opfunc = vim.opt.operatorfunc
  M.old_winnr = vim.api.nvim_get_current_win()
  M.old_cursor_position = vim.api.nvim_win_get_cursor(M.old_winnr)
  vim.opt.operatorfunc = ("v:lua.require'gitlab.reviewer'.execute_callback'%s'"):format(cb)
  -- Use the operator count before motion to allow, e.g., 2cc == c2c
  local count = M.operator_count > 0 and tostring(M.operator_count) or ""
  vim.api.nvim_feedkeys("g@" .. count, "n", false)
end

---Set keymaps for creating comments, suggestions and for jumping to discussion tree.
---@param bufnr integer Number of the buffer for which the keybindings will be created
M.set_keymaps = function(bufnr)
  if bufnr == nil or not vim.api.nvim_buf_is_loaded(bufnr) then
    return
  end
  -- Require keymaps only after user settings have been merged with defaults
  local keymaps = require("gitlab.state").settings.keymaps
  if keymaps.disable_all or keymaps.reviewer.disable_all then
    return
  end

  -- Set mappings for creating comments
  if keymaps.reviewer.create_comment ~= false then
    -- Set keymap for repeated operator keybinding
    -- FIXME: Replace this by explicitly mapping repeated keymap in normal mode. The way it is now,
    -- pressing `keymaps.reviewer.create_comment` in *any* operator-pending mode (e.g., after
    -- pressing `d` for delete), triggers comment creation!
    vim.keymap.set("o", keymaps.reviewer.create_comment, function()
      -- The "V" in "V%d$" forces linewise motion, see `:h o_V`
      vim.api.nvim_cmd({ cmd = "normal", bang = true, args = { string.format("V%d$", vim.v.count1) } }, {})
    end, {
      buffer = bufnr,
      desc = "Create comment for [count] lines",
      nowait = keymaps.reviewer.create_comment_nowait,
    })

    -- Set operator keybinding
    vim.keymap.set(
      "n",
      keymaps.reviewer.create_comment,
      function()
        M.operator_count = vim.v.count
        M.execute_operatorfunc("create_multiline_comment")
      end,
      { buffer = bufnr, desc = "Create comment for range of motion", nowait = keymaps.reviewer.create_comment_nowait }
    )
    vim.keymap.set("v", keymaps.reviewer.create_comment, function()
      require("gitlab").create_multiline_comment()
    end, {
      buffer = bufnr,
      desc = "Create comment for selected text",
      nowait = keymaps.reviewer.create_comment_nowait,
    })
  end

  -- Set mappings for creating suggestions
  if keymaps.reviewer.create_suggestion ~= false then
    -- Set keymap for repeated operator keybinding
    -- FIXME: Fix the same problem as for keymaps.reviewer.create_comment.
    vim.keymap.set("o", keymaps.reviewer.create_suggestion, function()
      -- The "V" in "V%d$" forces linewise motion, see `:h o_V`
      vim.api.nvim_cmd({ cmd = "normal", bang = true, args = { string.format("V%d$", vim.v.count1) } }, {})
    end, {
      buffer = bufnr,
      desc = "Create suggestion for [count] lines",
      nowait = keymaps.reviewer.create_suggestion_nowait,
    })

    -- Set operator keybinding
    vim.keymap.set("n", keymaps.reviewer.create_suggestion, function()
      M.operator_count = vim.v.count
      M.operator = keymaps.reviewer.create_suggestion
      M.execute_operatorfunc("create_comment_suggestion")
    end, {
      buffer = bufnr,
      desc = "Create suggestion for range of motion",
      nowait = keymaps.reviewer.create_suggestion_nowait,
    })

    -- Set visual mode keybinding
    vim.keymap.set("v", keymaps.reviewer.create_suggestion, function()
      require("gitlab").create_comment_suggestion()
    end, {
      buffer = bufnr,
      desc = "Create suggestion for selected text",
      nowait = keymaps.reviewer.create_suggestion_nowait,
    })
  end

  -- Set mapping for moving to discussion tree
  if keymaps.reviewer.move_to_discussion_tree ~= false then
    vim.keymap.set("n", keymaps.reviewer.move_to_discussion_tree, function()
      require("gitlab").move_to_discussion_tree_from_diagnostic()
    end, { buffer = bufnr, desc = "Move to discussion", nowait = keymaps.reviewer.move_to_discussion_tree_nowait })
  end
end

---Delete keymaps from reviewer buffers.
---@param bufnr integer Number of the buffer from which the keybindings will be removed
local del_keymaps = function(bufnr)
  if bufnr == nil or not vim.api.nvim_buf_is_loaded(bufnr) then
    return
  end
  -- Require keymaps only after user settings have been merged with defaults
  local keymaps = require("gitlab.state").settings.keymaps
  if keymaps.disable_all or keymaps.reviewer.disable_all then
    return
  end
  for _, func in ipairs({ "create_comment", "create_suggestion" }) do
    if keymaps.reviewer[func] ~= false then
      for _, mode in ipairs({ "n", "o", "v" }) do
        pcall(vim.api.nvim_buf_del_keymap, bufnr, mode, keymaps.reviewer[func])
      end
    end
  end
  if keymaps.reviewer.move_to_discussion_tree ~= false then
    pcall(vim.api.nvim_buf_del_keymap, bufnr, "n", keymaps.reviewer.move_to_discussion_tree)
  end
end

---Set up autocommands to set and unset buffer-local options and keymaps.
M.set_reviewer_autocommands = function(bufnr)
  local group = vim.api.nvim_create_augroup("gitlab.diffview.autocommand.win_enter." .. bufnr, {})
  vim.api.nvim_create_autocmd({ "WinEnter", "BufWinEnter" }, {
    group = group,
    buffer = bufnr,
    callback = function()
      -- These autocommands manage the reviewer's own two windows, but they are
      -- buffer-local and Diffview shares a revision's buffer across views, so the same
      -- buffer shows up in the commit browser's tab. Acting there would strip the browse
      -- keymaps and make the blob writable. Gate matches set_callback_for_buf_read.
      if not (vim.api.nvim_get_current_tabpage() == M.tabid or (M.is_open and M.tabid == nil)) then
        return
      end
      if vim.api.nvim_get_current_win() == M.buf_winids[bufnr] then
        M.stored_win = vim.api.nvim_get_current_win()
        u.switch_can_edit_buf(bufnr, false)
        M.set_keymaps(bufnr)
      else
        -- Only make the local file modifiable, not the diffview buffer for the old revision
        if M.diffview_layout.b.id == M.buf_winids[bufnr] then
          u.switch_can_edit_buf(bufnr, true)
        end
        del_keymaps(bufnr)
      end
    end,
  })
end

---Update the stored winid for a given reviewer buffer.
---This is necessary for the M.set_reviewer_autocommands function to work correctly in
---cases like when the user closes one of the original reviewer windows and Diffview
---automatically creates a new pair of reviewer windows or the user wipes out a buffer
---and Diffview reloads it with a different ID.
M.update_winid_for_buffer = function(bufnr)
  M.buf_winids[bufnr] = vim.fn.bufwinid(bufnr)
end

return M
