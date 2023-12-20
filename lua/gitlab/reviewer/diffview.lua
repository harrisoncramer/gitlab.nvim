-- This Module contains all of the reviewer code for diffview
local u = require("gitlab.utils")
local state = require("gitlab.state")
local async_ok, async = pcall(require, "diffview.async")
local diffview_lib = require("diffview.lib")

local M = {
  bufnr = nil,
  tabnr = nil,
}

M.open = function()
  local diff_refs = state.INFO.diff_refs
  if diff_refs == nil then
    u.notify("Gitlab did not provide diff refs required to review this MR", vim.log.levels.ERROR)
    return
  end

  if diff_refs.base_sha == "" or diff_refs.head_sha == "" then
    u.notify("Merge request contains no changes", vim.log.levels.ERROR)
    return
  end

  vim.api.nvim_command(string.format("DiffviewOpen %s..%s", diff_refs.base_sha, diff_refs.head_sha))
  M.tabnr = vim.api.nvim_get_current_tabpage()

  if state.INFO.has_conflicts then
    u.notify("This merge request has conflicts!", vim.log.levels.WARN)
  end

  local group = vim.api.nvim_create_augroup("gitlab.diffview.autocommand.close", {})
  vim.api.nvim_create_autocmd("User", {
    pattern = { "DiffviewViewClosed" },
    group = group,
    callback = function()
      --Check if our diffview tab was closed
      if vim.api.nvim_tabpage_is_valid(M.tabnr) then
        M.tabnr = nil
      end
    end,
  })

  if state.settings.discussion_tree.auto_open then
    local discussions = require("gitlab.actions.discussions")
    discussions.close()
    discussions.toggle()
  end
end

M.close = function()
  vim.cmd("DiffviewClose")
  local discussions = require("gitlab.actions.discussions")
  discussions.close()
end

M.jump = function(file_name, new_line, old_line, opts)
  if M.tabnr == nil then
    u.notify("Can't jump to Diffvew. Is it open?", vim.log.levels.ERROR)
    return
  end
  vim.api.nvim_set_current_tabpage(M.tabnr)
  vim.cmd("DiffviewFocusFiles")
  local view = diffview_lib.get_current_view()
  if view == nil then
    u.notify("Could not find Diffview view", vim.log.levels.ERROR)
    return
  end
  local files = view.panel:ordered_file_list()
  local layout = view.cur_layout
  for _, file in ipairs(files) do
    if file.path == file_name then
      if not async_ok then
        u.notify("Could not load Diffview async", vim.log.levels.ERROR)
        return
      end
      async.await(view:set_file(file))
      -- TODO: Ranged comments on unchanged lines will have both a
      -- new line and a old line. We need to distinguish them somehow from
      -- range comments (which also have this) so that we can know
      -- which buffer to jump to. Right now, we jump to the wrong
      -- buffer for ranged comments on unchanged lines.
      if new_line ~= nil and not opts.is_undefined_type then
        layout.b:focus()
        vim.api.nvim_win_set_cursor(0, { tonumber(new_line), 0 })
      elseif old_line ~= nil then
        layout.a:focus()
        vim.api.nvim_win_set_cursor(0, { tonumber(old_line), 0 })
      end
      break
    end
  end
end

---Get the location of a line within the diffview. If range is specified, then also the location
---of the lines in range.
---@param range LineRange | nil Line range to get location for
---@return ReviewerInfo | nil nil is returned only if error was encountered
M.get_location = function(range)
  if M.tabnr == nil then
    u.notify("Diffview reviewer must be initialized first")
    return
  end
  local bufnr = vim.api.nvim_get_current_buf()
  local current_line = vim.api.nvim_win_get_cursor(0)[1]

  -- check if we are in the diffview tab
  local tabnr = vim.api.nvim_get_current_tabpage()
  if tabnr ~= M.tabnr then
    u.notify("Line location can only be determined within reviewer window")
    return
  end

  -- check if we are in the diffview buffer
  local view = diffview_lib.get_current_view()
  if view == nil then
    u.notify("Could not find Diffview view", vim.log.levels.ERROR)
    return
  end
  local layout = view.cur_layout
  local result = {}
  local type
  local is_new

  if
    layout.a.file.bufnr == bufnr
    or (M.lines_are_same(view.cur_layout) and layout.b.file.bufnr == bufnr and range == nil)
  then
    result.file_name = layout.a.file.path
    result.old_line = current_line
    type = "old"
    is_new = false
  elseif layout.b.file.bufnr == bufnr then
    result.file_name = layout.b.file.path
    result.new_line = current_line
    type = "new"
    is_new = true
  else
    u.notify("Line location can only be determined within reviewer window")
    return
  end

  local hunks = u.parse_hunk_headers(result.file_name, state.INFO.target_branch)
  if hunks == nil then
    u.notify("Could not parse hunks", vim.log.levels.ERROR)
    return
  end

  local current_line_info
  if is_new then
    current_line_info = u.get_lines_from_hunks(hunks, result.new_line, is_new)
  else
    current_line_info = u.get_lines_from_hunks(hunks, result.old_line, is_new)
  end

  -- If single line comment is outside of changed lines then we need to specify both new line and old line
  -- otherwise the API returns error.
  -- https://docs.gitlab.com/ee/api/discussions.html#create-a-new-thread-in-the-merge-request-diff
  if not current_line_info.in_hunk then
    result.old_line = current_line_info.old_line
    result.new_line = current_line_info.new_line
  end

  vim.print(current_line_info)

  -- If users leave single-line comments in the new buffer that should be in the old buffer, we can
  -- tell because the line will not have changed. Send the correct payload.
  if M.lines_are_same(view.cur_layout) and layout.b.file.bufnr == bufnr and range == nil then
    local a_win = u.get_win_from_buf(layout.a.file.bufnr)
    local a_cursor = vim.api.nvim_win_get_cursor(a_win)[1]
    result.old_line = a_cursor
    result.new_line = a_cursor
    type = "old"
  end

  if range == nil then
    return result
  end

  -- FIXME #2: If line has new_line properties, then don't show diagnostics in old file...
  result.range_info = { start = {}, ["end"] = {} }
  if current_line == range.start_line then
    result.range_info.start.old_line = current_line_info.old_line
    result.range_info.start.new_line = current_line_info.new_line
    result.range_info.start.type = type
  else
    local start_line_info = u.get_lines_from_hunks(hunks, range.start_line, is_new)
    result.range_info.start.old_line = start_line_info.old_line
    result.range_info.start.new_line = start_line_info.new_line
    result.range_info.start.type = type
  end

  if current_line == range.end_line then
    result.range_info["end"].old_line = current_line_info.old_line
    result.range_info["end"].new_line = current_line_info.new_line
    result.range_info["end"].type = type
  else
    local end_line_info = u.get_lines_from_hunks(hunks, range.end_line, is_new)
    result.range_info["end"].old_line = end_line_info.old_line
    result.range_info["end"].new_line = end_line_info.new_line
    result.range_info["end"].type = type
  end

  return result
end

---Return content between start_line and end_line
---@param start_line integer
---@param end_line integer
---@return string[]
M.get_lines = function(start_line, end_line)
  return vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
end

---@return boolean
M.lines_are_same = function(layout)
  local a_win = u.get_win_from_buf(layout.a.file.bufnr)
  local b_win = u.get_win_from_buf(layout.b.file.bufnr)
  local a_cursor = vim.api.nvim_win_get_cursor(a_win)[1]
  local b_cursor = vim.api.nvim_win_get_cursor(b_win)[1]
  local line_a = u.get_line_content(layout.a.file.bufnr, a_cursor)
  local line_b = u.get_line_content(layout.b.file.bufnr, b_cursor)
  return line_a == line_b
end

---Get currently shown file
M.get_current_file = function()
  local view = diffview_lib.get_current_view()
  if not view then
    return
  end
  return view.panel.cur_file.path
end

---Place a sign in currently reviewed file. Use new line for identifing lines after changes, old
---line for identifing lines before changes and both if line was not changed.
---@param signs SignTable[] table of signs. See :h sign_placelist
---@param type string "new" if diagnostic should be in file after changes else "old"
M.place_sign = function(signs, type)
  local view = diffview_lib.get_current_view()
  if not view then
    return
  end
  if type == "new" then
    for _, sign in ipairs(signs) do
      sign.buffer = view.cur_layout.b.file.bufnr
    end
  elseif type == "old" then
    for _, sign in ipairs(signs) do
      sign.buffer = view.cur_layout.a.file.bufnr
    end
  end
  vim.fn.sign_placelist(signs)
end

---Set diagnostics in currently reviewed file.
---@param namespace integer namespace for diagnostics
---@param diagnostics table see :h vim.diagnostic.set
---@param type string "new" if diagnostic should be in file after changes else "old"
---@param opts table? see :h vim.diagnostic.set
M.set_diagnostics = function(namespace, diagnostics, type, opts)
  local view = diffview_lib.get_current_view()
  if not view then
    return
  end
  if type == "new" and view.cur_layout.b.file.bufnr then
    vim.diagnostic.set(namespace, view.cur_layout.b.file.bufnr, diagnostics, opts)
  elseif type == "old" and view.cur_layout.a.file.bufnr then
    vim.diagnostic.set(namespace, view.cur_layout.a.file.bufnr, diagnostics, opts)
  end
end

---Diffview exposes events which can be used to setup autocommands.
---@param callback fun(opts: table) - for more information about opts see callback in :h nvim_create_autocmd
M.set_callback_for_file_changed = function(callback)
  local group = vim.api.nvim_create_augroup("gitlab.diffview.autocommand.file_changed", {})
  vim.api.nvim_create_autocmd("User", {
    pattern = { "DiffviewDiffBufWinEnter", "DiffviewViewEnter" },
    group = group,
    callback = function(...)
      if M.tabnr == vim.api.nvim_get_current_tabpage() then
        callback(...)
      end
    end,
  })
end

---Diffview exposes events which can be used to setup autocommands.
---@param callback fun(opts: table) - for more information about opts see callback in :h nvim_create_autocmd
M.set_callback_for_reviewer_leave = function(callback)
  local group = vim.api.nvim_create_augroup("gitlab.diffview.autocommand.leave", {})
  vim.api.nvim_create_autocmd("User", {
    pattern = { "DiffviewViewLeave", "DiffviewViewClosed" },
    group = group,
    callback = function(...)
      if M.tabnr == vim.api.nvim_get_current_tabpage() then
        callback(...)
      end
    end,
  })
end

return M
