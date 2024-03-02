local diffview_lib = require("diffview.lib")
local discussion_tree = require("gitlab.actions.discussions.tree")
local common = require("gitlab.indicators.common")
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

---Takes some range information and data about a discussion
---and creates a diagnostic to be placed in the reviewer
---@param range_info table
---@param discussion Discussion
---@return Diagnostic
local function create_diagnostic(range_info, discussion)
  local message = ""
  for _, note in ipairs(discussion.notes) do
    message = message .. discussion_tree.build_note_header(note) .. "\n" .. note.body .. "\n"
  end

  local diagnostic = {
    message = message,
    col = 0,
    severity = state.settings.discussion_diagnostic.severity,
    user_data = { discussion_id = discussion.id, header = discussion_tree.build_note_header(discussion.notes[1]) },
    source = "gitlab",
    code = state.settings.discussion_diagnostic.code,
  }
  return vim.tbl_deep_extend("force", diagnostic, range_info)
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
end

---Refresh the diagnostics for the currently reviewed file
---@param discussions Discussion[]
M.refresh_diagnostics = function(discussions)
  M.clear_diagnostics()
  local filtered_discussions = common.filter_placeable_discussions(discussions)
  if filtered_discussions == nil then
    return
  end

  set_diagnostics_in_new_sha(
    diagnostics_namespace,
    M.parse_new_diagnostics(filtered_discussions),
    state.settings.discussion_diagnostic.display_opts
  )
  set_diagnostics_in_old_sha(
    diagnostics_namespace,
    M.parse_old_diagnostics(filtered_discussions),
    state.settings.discussion_diagnostic.display_opts
  )
end

---Iterates over each discussion and returns a list of tables with sign
---data, for instance group, priority, line number etc for the new SHA
---@param discussions Discussion[]
---@return DiagnosticTable[]
M.parse_new_diagnostics = function(discussions)
  return List.new(discussions):filter(common.is_new_sha):filter(common.is_single_line):map(function(discussion)
    local first_note = discussion.notes[1]
    return create_diagnostic({
      lnum = first_note.position.new_line - 1,
    }, discussion)
  end)
end

---Iterates over each discussion and returns a list of tables with sign
---data, for instance group, priority, line number etc for the old SHA
---@param discussions Discussion[]
---@return DiagnosticTable[]
M.parse_old_diagnostics = function(discussions)
  local res = List.new(discussions):filter(common.is_old_sha):filter(common.is_single_line):map(function(discussion)
    local first_note = discussion.notes[1]
    return create_diagnostic({
      lnum = first_note.position.old_line - 1,
    }, discussion)
  end)
  return res
end

return M
