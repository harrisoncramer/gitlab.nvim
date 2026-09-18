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

  local view = require("gitlab.reviewer").diffview
  if view == nil then
    u.notify("Could not find Diffview view", vim.log.levels.ERROR)
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
  if bufnr and vim.api.nvim_buf_get_name(bufnr) == "diffview://null" then
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
      set_diagnostics(
        M.diagnostics_namespace,
        bufnr,
        M.parse_diagnostics(old_discussions),
        indicators_common.create_display_opts()
      )
    elseif bufnr == view.cur_layout.b.file.bufnr then
      set_diagnostics(
        M.diagnostics_namespace,
        bufnr,
        M.parse_diagnostics(new_discussions),
        indicators_common.create_display_opts()
      )
    end
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
