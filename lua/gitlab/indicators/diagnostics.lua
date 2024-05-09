local u = require("gitlab.utils")
local diffview_lib = require("diffview.lib")
local indicators_common = require("gitlab.indicators.common")
local actions_common = require("gitlab.actions.common")
local List = require("gitlab.utils.list")
local state = require("gitlab.state")
local discussion_sign_name = "gitlab_discussion"

local M = {}
local diagnostics_namespace = vim.api.nvim_create_namespace(discussion_sign_name)
M.diagnostics_namespace = diagnostics_namespace
M.discussion_sign_name = discussion_sign_name
M.clear_diagnostics = function()
  vim.diagnostic.reset(diagnostics_namespace)
end

-- Display options for the diagnostic
local create_display_opts = function()
  return {
    virtual_text = state.settings.discussion_signs.virtual_text,
    severity_sort = true,
    underline = false,
    signs = state.settings.discussion_signs.use_diagnostic_signs,
  }
end

---Takes some range information and data about a discussion
---and creates a diagnostic to be placed in the reviewer
---@param range_info table
---@param d_or_n Discussion|DraftNote
---@return Diagnostic
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

---Creates a single line diagnostic
---@param d_or_n Discussion|DraftNote
---@return Diagnostic
local create_single_line_diagnostic = function(d_or_n)
  local linnr = actions_common.get_line_number(d_or_n.id)
  return create_diagnostic({
    lnum = linnr - 1,
  }, d_or_n)
end

---Creates a mutli-line line diagnostic
---@param d_or_n Discussion|DraftNote
---@return Diagnostic
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

---Set diagnostics in currently new SHA.
---@param namespace number namespace for diagnostics
---@param diagnostics table see :h vim.diagnostic.set
---@param opts table? see :h vim.diagnostic.set
local set_diagnostics_in_new_sha = function(namespace, diagnostics, opts)
  local view = diffview_lib.get_current_view()
  if not view then
    return
  end
  vim.diagnostic.set(namespace, view.cur_layout.b.file.bufnr, diagnostics, opts)
  require("gitlab.indicators.signs").set_signs(diagnostics, view.cur_layout.b.file.bufnr)
end

---Set diagnostics in old SHA.
---@param namespace number namespace for diagnostics
---@param diagnostics table see :h vim.diagnostic.set
---@param opts table? see :h vim.diagnostic.set
local set_diagnostics_in_old_sha = function(namespace, diagnostics, opts)
  local view = diffview_lib.get_current_view()
  if not view then
    return
  end
  vim.diagnostic.set(namespace, view.cur_layout.a.file.bufnr, diagnostics, opts)
  require("gitlab.indicators.signs").set_signs(diagnostics, view.cur_layout.a.file.bufnr)
end

---Refresh the diagnostics for the currently reviewed file
M.refresh_diagnostics = function()
  local ok, err = pcall(function()
    require("gitlab.indicators.signs").clear_signs()
    M.clear_diagnostics()
    local filtered_discussions = indicators_common.filter_placeable_discussions()
    if filtered_discussions == nil then
      return
    end

    local new_diagnostics = M.parse_new_diagnostics(filtered_discussions)
    set_diagnostics_in_new_sha(diagnostics_namespace, new_diagnostics, create_display_opts())

    local old_diagnostics = M.parse_old_diagnostics(filtered_discussions)
    set_diagnostics_in_old_sha(diagnostics_namespace, old_diagnostics, create_display_opts())
  end)

  if not ok then
    u.notify(string.format("Error setting diagnostics: %s", err), vim.log.levels.ERROR)
  end
end

---Iterates over each discussion and returns a list of tables with sign
---data, for instance group, priority, line number etc for the new SHA
---@param discussions Discussion[]
---@return DiagnosticTable[]
M.parse_new_diagnostics = function(discussions)
  local new_diagnostics = List.new(discussions):filter(indicators_common.is_new_sha)
  local single_line = new_diagnostics:filter(indicators_common.is_single_line):map(create_single_line_diagnostic)
  local multi_line = new_diagnostics:filter(indicators_common.is_multi_line):map(create_multiline_diagnostic)
  return u.combine(single_line, multi_line)
end

---Iterates over each discussion and returns a list of tables with sign
---data, for instance group, priority, line number etc for the old SHA
---@param discussions Discussion[]
---@return DiagnosticTable[]
M.parse_old_diagnostics = function(discussions)
  local old_diagnostics = List.new(discussions):filter(indicators_common.is_old_sha)
  local single_line = old_diagnostics:filter(indicators_common.is_single_line):map(create_single_line_diagnostic)
  local multi_line = old_diagnostics:filter(indicators_common.is_multi_line):map(create_multiline_diagnostic)
  return u.combine(single_line, multi_line)
end

return M
