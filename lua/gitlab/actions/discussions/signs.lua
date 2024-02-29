local List = require("gitlab.utils.list")
local state = require("gitlab.state")
local u = require("gitlab.utils")
local reviewer = require("gitlab.reviewer")
local diffview_lib = require("diffview.lib")
local discussion_sign_name = "gitlab_discussion"
local discussion_helper_sign_start = "gitlab_discussion_helper_start"
local discussion_helper_sign_mid = "gitlab_discussion_helper_mid"
local discussion_helper_sign_end = "gitlab_discussion_helper_end"
local diagnostics_namespace = vim.api.nvim_create_namespace(discussion_sign_name)

local M = {}
M.diagnostics_namespace = diagnostics_namespace

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

---Takes in a note and creates a sign to be placed in the reviewer
---@param note Note
---@return SignTable
local function create_sign(note)
  return {
    id = note.id,
    name = discussion_sign_name,
    group = discussion_sign_name,
    priority = state.settings.discussion_sign.priority,
    buffer = nil,
  }
end

---@param discussion Discussion
---@return boolean
local function place_in_old_sha(discussion)
  local first_note = discussion.notes[1]
  return first_note.position.old_line ~= nil
end

---Takes in a list of discussions and turns them into a list of
---signs to be placed in the old SHA
---@param discussions Discussion[]
---@return SignTable[]
local function parse_old_signs_from_discussions(discussions)
  local view = diffview_lib.get_current_view()
  if not view then
    return {}
  end

  return List.new(discussions)
    :filter(function(discussion)
      local first_note = discussion.notes[1]
      local line_range = first_note.position.line_range
      return line_range == nil
    end)
    :map(function(discussion)
      return discussion.notes[1]
    end)
    :map(function(note)
      return create_sign(note)
    end)
end

---Refresh the discussion signs for currently loaded file in reviewer For convinience we use same
---string for sign name and sign group ( currently there is only one sign needed)
---@param discussions Discussion[]
M.refresh_signs = function(discussions)
  local filtered_discussions = M.filter_discussions(discussions)
  if filtered_discussions == nil then
    vim.diagnostic.reset(diagnostics_namespace)
    return
  end

  local old_signs = parse_old_signs_from_discussions(filtered_discussions)
  if old_signs == nil then
    vim.notify("Could not parse old signs from discussions", vim.log.levels.ERROR)
    return
  end

  -- TODO: This is not working, the signs are not being placed
  vim.fn.sign_unplace(discussion_sign_name)
  vim.fn.sign_placelist(old_signs)
end

---Clear all signs and diagnostics
M.clear_signs_and_diagnostics = function()
  vim.fn.sign_unplace(discussion_sign_name)
  vim.diagnostic.reset(diagnostics_namespace)
end

---Refresh the diagnostics for the currently reviewed file
---@param discussions Discussion[]
M.refresh_diagnostics = function(discussions)
  local filtered_discussions = M.filter_discussions(discussions)
  if filtered_discussions == nil then
    vim.diagnostic.reset(diagnostics_namespace)
    return
  end

  vim.diagnostic.reset(diagnostics_namespace)
  -- reviewer.set_diagnostics_in_new_sha(
  --   diagnostics_namespace,
  --   M.parse_new_diagnostics(filtered_discussions),
  --   state.settings.discussion_diagnostic.display_opts
  -- )
  reviewer.set_diagnostics_in_old_sha(
    diagnostics_namespace,
    M.parse_old_diagnostics(filtered_discussions),
    state.settings.discussion_diagnostic.display_opts
  )
end

---Filter all discussions which are relevant for currently visible signs and diagnostics.
---@return Discussion[]?
M.filter_discussions = function(all_discussions)
  if type(all_discussions) ~= "table" then
    return
  end
  local file = reviewer.get_current_file()
  if not file then
    return
  end
  return List.new(all_discussions):filter(function(discussion)
    local first_note = discussion.notes[1]
    return type(first_note.position) == "table"
      --Do not include unlinked notes
      and (first_note.position.new_path == file or first_note.position.old_path == file)
      --Skip resolved discussions if user wants to
      and not (state.settings.discussion_sign_and_diagnostic.skip_resolved_discussion and first_note.resolvable and first_note.resolved)
      --Skip discussions from old revisions
      and not (
        state.settings.discussion_sign_and_diagnostic.skip_old_revision_discussion
        and u.from_iso_format_date_to_timestamp(first_note.created_at)
          <= u.from_iso_format_date_to_timestamp(state.MR_REVISIONS[1].created_at)
      )
  end)
end

---Define signs for discussions if not already defined
M.setup_signs = function()
  local discussion_sign = state.settings.discussion_sign
  local signs = {
    [discussion_sign_name] = discussion_sign.text,
    [discussion_helper_sign_start] = discussion_sign.helper_signs.start,
    [discussion_helper_sign_mid] = discussion_sign.helper_signs.mid,
    [discussion_helper_sign_end] = discussion_sign.helper_signs["end"],
  }
  for sign_name, sign_text in pairs(signs) do
    if #vim.fn.sign_getdefined(sign_name) == 0 then
      vim.fn.sign_define(sign_name, {
        text = sign_text,
        linehl = discussion_sign.linehl,
        texthl = discussion_sign.texthl,
        culhl = discussion_sign.culhl,
        numhl = discussion_sign.numhl,
      })
    end
  end
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
  if discussions == nil then
    return {}
  end
  local old_discussions = List.new(discussions):filter(place_in_old_sha)
  vim.print(#old_discussions)

  -- Keep in mind that diagnostic line numbers use 0-based indexing while line numbers use
  -- 1-based indexing
  local single_line_diagnostics = old_discussions
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

  return single_line_diagnostics
end

---Parse line code and return old and new line numbers
---@param line_code string gitlab line code -> 588440f66559714280628a4f9799f0c4eb880a4a_10_10
---@return number?
M.parse_line_code = function(line_code)
  local line_code_regex = "%w+_(%d+)_(%d+)"
  local old_line, new_line = line_code:match(line_code_regex)
  return tonumber(old_line), tonumber(new_line)
end

---Build note header from note.
---@param note Note
---@return string
M.build_note_header = function(note)
  return "@" .. note.author.username .. " " .. u.time_since(note.created_at)
end

return M
