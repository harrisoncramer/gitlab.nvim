local u = require("gitlab.utils")
local indicators_common = require("gitlab.indicators.common")
local actions_common = require("gitlab.actions.common")
local List = require("gitlab.utils.list")
local state = require("gitlab.state")

local M = {}

M.discussion_sign_name = "gitlab_discussion"
M.diagnostics_namespace = vim.api.nvim_create_namespace(M.discussion_sign_name)

---Clear the Gitlab Discussion diagnostic namespace.
M.clear_diagnostics = function()
  vim.diagnostic.reset(M.diagnostics_namespace)
end

---Return display options for the diagnostics.
---@return vim.diagnostic.Opts
local create_display_opts = function()
  return {
    virtual_text = state.settings.discussion_signs.virtual_text,
    severity_sort = true,
    underline = false,
    signs = state.settings.discussion_signs.use_diagnostic_signs,
  }
end

---@class RangeInfo
---@field lnum integer The starting line of the diagnostic (0-indexed)
---@field end_lnum? integer The final line of the diagnostic (0-indexed)

---Return a diagnostic to be placed in the reviewer.
---@param range_info RangeInfo Information about diagnostic position
---@param d_or_n Discussion|DraftNote The data to build the diagnostic content from
---@return vim.Diagnostic.Set
local function create_diagnostic(range_info, d_or_n)
  local first_note = indicators_common.get_first_note(d_or_n)
  local header = actions_common.build_note_header(first_note)
  local message = header
  if d_or_n.notes then
    for _, note in ipairs(d_or_n.notes or {}) do
      message = message .. "\n" .. note.body .. "\n"
    end
  else
    message = message .. "\n" .. d_or_n.note .. "\n"
  end

  local diagnostic = {
    message = message,
    col = 0,
    severity = state.settings.discussion_signs.severity,
    user_data = { discussion_id = d_or_n.id, header = header },
    source = "gitlab",
    code = "gitlab.nvim",
  }
  return vim.tbl_deep_extend("force", diagnostic, range_info)
end

---Create a single line diagnostic.
---@param d_or_n Discussion|DraftNote
---@return vim.Diagnostic.Set
local create_single_line_diagnostic = function(d_or_n)
  local linnr = actions_common.get_line_number(d_or_n.id)
  return create_diagnostic({
    lnum = linnr - 1,
  }, d_or_n)
end

---Create a mutli-line line diagnostic.
---@param d_or_n Discussion|DraftNote
---@return vim.Diagnostic.Set
local create_multiline_diagnostic = function(d_or_n)
  local first_note = indicators_common.get_first_note(d_or_n)
  local line_range = first_note.position.line_range
  if line_range == nil then
    error("Parsing multi-line comment but note does not contain line range")
  end

  local start_line, end_line, _ = actions_common.get_line_numbers_for_range(
    first_note.position.old_line,
    first_note.position.new_line,
    line_range.start.line_code,
    line_range["end"].line_code
  )

  return create_diagnostic({
    lnum = start_line - 1,
    end_lnum = end_line - 1,
  }, d_or_n)
end

---Set diagnostics in the given buffer.
---@param namespace integer Namespace ID for diagnostics
---@param bufnr integer The bufnr for placing the diagnostics
---@param diagnostics vim.Diagnostic.Set[] A list of diagnostics definitions
---@param opts? vim.diagnostic.Opts see :h vim.diagnostic.set
local set_diagnostics = function(namespace, bufnr, diagnostics, opts)
  vim.diagnostic.set(namespace, bufnr, diagnostics, opts)
  require("gitlab.indicators.signs").set_signs(diagnostics, bufnr)
end

---Refresh diagnostics for all files, and place diagnostics for the currently visible buffers.
M.refresh_diagnostics = function()
  require("gitlab.indicators.signs").clear_signs()
  M.clear_diagnostics()
  M.placeable_discussions = indicators_common.filter_placeable_discussions()

  local reviewer = require("gitlab.reviewer")
  local view = reviewer.diffview
  if view == nil then
    -- A nil view means either no reviewer was opened (commenting from the commit browser
    -- lands here) or an open one lost its view. Only the second is an error.
    if reviewer.is_open then
      u.notify("Could not find Diffview view", vim.log.levels.ERROR)
    end
    return
  end
  M.place_diagnostics(view.cur_layout.a.file.bufnr)
  M.place_diagnostics(view.cur_layout.b.file.bufnr)
end

---Filter and place the diagnostics for the given buffer.
---@param bufnr integer The bufnr for placing the diagnostics
M.place_diagnostics = function(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  if not state.settings.discussion_signs.enabled then
    return
  end
  -- TODO: Use cur_layout = require("gitlab.reviewer").diffview_layout instead.
  local view = require("gitlab.reviewer").diffview
  if view == nil then
    u.notify("Could not find Diffview view", vim.log.levels.ERROR)
    return
  end
  if vim.api.nvim_buf_get_name(bufnr) == "diffview://null" then
    return
  end

  local ok, err = pcall(function()
    local file_discussions = List.new(M.placeable_discussions):filter(function(discussion_or_note)
      local note = discussion_or_note.notes and discussion_or_note.notes[1] or discussion_or_note
      return note.position.new_path == view.cur_layout.b.file.path
        or note.position.old_path == view.cur_layout.a.file.path
    end)

    if #file_discussions == 0 then
      return
    end

    local new_discussions, old_discussions = List.new(file_discussions):partition(indicators_common.is_new_sha)

    if bufnr == view.cur_layout.a.file.bufnr then
      set_diagnostics(M.diagnostics_namespace, bufnr, M.parse_diagnostics(old_discussions), create_display_opts())
    elseif bufnr == view.cur_layout.b.file.bufnr then
      set_diagnostics(M.diagnostics_namespace, bufnr, M.parse_diagnostics(new_discussions), create_display_opts())
    end
  end)

  if not ok then
    u.notify(string.format("Error setting diagnostics: %s", err), vim.log.levels.ERROR)
  end
end

---Create the diagnostic for a note on a line the browsed commit deletes.
---Gitlab renumbers a stored commit comment's top-level old_line to the MR base wherever the
---line exists there, but leaves the line range in the commit's own numbering, which is what
---the browser's old side shows. A note without a range was not written by this plugin, and
---its old_line is all there is (actions/common.lua resolves the jump the same way).
---@param d_or_n Discussion|DraftNote
---@return vim.Diagnostic.Set
local create_commit_old_side_diagnostic = function(d_or_n)
  local position = indicators_common.get_first_note(d_or_n).position
  local line_range = position.line_range
  if line_range == nil then
    return create_diagnostic({ lnum = position.old_line - 1 }, d_or_n)
  end
  return create_diagnostic({ lnum = line_range.start.old_line - 1, end_lnum = line_range["end"].old_line - 1 }, d_or_n)
end

---Place the diagnostics for the comments anchored to the commit the browser shows, on one
---side of its diff. Diffview reuses a revision's buffer across views, so the buffer is
---written even when the commit has no comments, to drop what another commit or the reviewer
---put there.
---@param bufnr integer Buffer holding one side of the browsed commit's diff
---@param sha string The commit currently browsed
---@param file_path string Path of the file shown, in the version that side holds
---@param on_old_side boolean True for the parent's version of the file (left window)
M.place_commit_diagnostics = function(bufnr, sha, file_path, on_old_side)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  if not state.settings.discussion_signs.enabled then
    return
  end

  local side_discussions = List.new(indicators_common.filter_commit_discussions(sha)):filter(function(d_or_n)
    local position = indicators_common.get_first_note(d_or_n).position
    if on_old_side then
      return position.old_path == file_path and indicators_common.is_old_sha(d_or_n)
    end
    return position.new_path == file_path and indicators_common.is_new_sha(d_or_n)
  end)

  local ok, err = pcall(function()
    local parsed = on_old_side and side_discussions:map(create_commit_old_side_diagnostic)
      or M.parse_diagnostics(side_discussions)
    set_diagnostics(M.diagnostics_namespace, bufnr, parsed, create_display_opts())
  end)

  if not ok then
    u.notify(string.format("Error setting diagnostics: %s", err), vim.log.levels.ERROR)
  end
end

---Return a list of diagnostics definitions parsed from discussions.
---@param discussions List<Discussion|DraftNote>
---@return vim.Diagnostic.Set[]
M.parse_diagnostics = function(discussions)
  local single_line, multi_line = discussions:partition(indicators_common.is_single_line)
  single_line = single_line:map(create_single_line_diagnostic)
  multi_line = multi_line:map(create_multiline_diagnostic)
  return u.combine(single_line, multi_line)
end

return M
