local u = require("gitlab.utils")
local reviewer = require("gitlab.reviewer")
local common = require("gitlab.actions.indicators.common")
local List = require("gitlab.utils.list")
local state = require("gitlab.state")
local discussion_sign_name = "gitlab_discussion"

local M = {}

local diagnostics_namespace = vim.api.nvim_create_namespace(discussion_sign_name)
M.diagnostics_namespace = diagnostics_namespace

---Build note header from note.
---@param note Note
---@return string
M.build_note_header = function(note)
  return "@" .. note.author.username .. " " .. u.time_since(note.created_at)
end

---@param discussion Discussion
---@return boolean
local function place_in_old_sha(discussion)
  local first_note = discussion.notes[1]
  return first_note.position.old_line ~= nil
end

---Takes some range information and data about a discussion
---and creates a diagnostic to be placed in the reviewer
---@param range_info table
---@param discussion Discussion
---@return Diagnostic
local function create_diagnostic(range_info, discussion)
  local message = ""
  for _, note in ipairs(discussion.notes) do
    message = message .. M.build_note_header(note) .. "\n" .. note.body .. "\n"
  end

  local diagnostic = {
    message = message,
    col = 0,
    severity = state.settings.discussion_diagnostic.severity,
    user_data = { discussion_id = discussion.id, header = M.build_note_header(discussion.notes[1]) },
    source = "gitlab",
    code = state.settings.discussion_diagnostic.code,
  }
  return vim.tbl_deep_extend("force", diagnostic, range_info)
end

---Refresh the diagnostics for the currently reviewed file
---@param discussions Discussion[]
M.refresh_diagnostics = function(discussions)
  vim.diagnostic.reset(diagnostics_namespace)
  local filtered_discussions = common.filter_discussions(discussions)
  if filtered_discussions == nil then
    return
  end

  reviewer.set_diagnostics_in_new_sha(
    diagnostics_namespace,
    M.parse_new_diagnostics(filtered_discussions),
    state.settings.discussion_diagnostic.display_opts
  )
  reviewer.set_diagnostics_in_old_sha(
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
  return {}
end

---Iterates over each discussion and returns a list of tables with sign
---data, for instance group, priority, line number etc for the old SHA
---@param discussions Discussion[]
---@return DiagnosticTable[]
M.parse_old_diagnostics = function(discussions)
  return List.new(discussions)
      :filter(place_in_old_sha)
      :filter(function(discussion)
        local first_note = discussion.notes[1]
        local line_range = first_note.position.line_range
        return line_range == nil
      end)
      :map(function(discussion)
        local first_note = discussion.notes[1]
        return {
          range_info = { lnum = first_note.position.old_line - 1 },
          discussion = discussion,
        }
      end)
      :map(function(d)
        return create_diagnostic(d.range_info, d.discussion)
      end)
end

return M
