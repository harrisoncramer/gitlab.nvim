local state = require("gitlab.state")
local u = require("gitlab.utils")
local reviewer = require("gitlab.reviewer")
local discussion_sign_name = "gitlab_discussion"
local discussion_helper_sign_start = "gitlab_discussion_helper_start"
local discussion_helper_sign_mid = "gitlab_discussion_helper_mid"
local discussion_helper_sign_end = "gitlab_discussion_helper_end"
local diagnostics_namespace = vim.api.nvim_create_namespace(discussion_sign_name)

local M = {}
M.diagnostics_namespace = diagnostics_namespace

---Parse line code and return old and new line numbers
---@param line_code string gitlab line code -> 588440f66559714280628a4f9799f0c4eb880a4a_10_10
---@return number?
---@return number?
local function _parse_line_code(line_code)
  local line_code_regex = "%w+_(%d+)_(%d+)"
  local old_line, new_line = line_code:match(line_code_regex)
  return tonumber(old_line), tonumber(new_line)
end

---Filter all discussions which are relevant for currently visible signs and diagnostscs.
---@return Discussion[]?
local filter_discussions_for_signs_and_diagnostics = function(all_discussions)
  if type(all_discussions) ~= "table" then
    return
  end
  local file = reviewer.get_current_file()
  if not file then
    return
  end
  local discussions = {}
  for _, discussion in ipairs(all_discussions) do
    local first_note = discussion.notes[1]
    if
      type(first_note.position) == "table"
      and (first_note.position.new_path == file or first_note.position.old_path == file)
    then
      if
        --Skip resolved discussions
        not (
          state.settings.discussion_sign_and_diagnostic.skip_resolved_discussion
          and first_note.resolvable
          and first_note.resolved
        )
        --Skip discussions from old revisions
        and not (
          state.settings.discussion_sign_and_diagnostic.skip_old_revision_discussion
          and u.from_iso_format_date_to_timestamp(first_note.created_at)
            <= u.from_iso_format_date_to_timestamp(state.MR_REVISIONS[1].created_at)
        )
      then
        table.insert(discussions, discussion)
      end
    end
  end
  return discussions
end

---Build note header from note.
---@param note Note
---@return string
local build_note_header = function(note)
  return "@" .. note.author.username .. " " .. u.time_since(note.created_at)
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

---Refresh the discussion signs for currently loaded file in reviewer For convinience we use same
---string for sign name and sign group ( currently there is only one sign needed)
M.refresh_signs = function(discussions)
  local diagnostics = filter_discussions_for_signs_and_diagnostics(discussions)
  if diagnostics == nil then
    vim.diagnostic.reset(diagnostics_namespace)
    return
  end

  local new_signs = {}
  local old_signs = {}
  for _, discussion in ipairs(diagnostics) do
    local first_note = discussion.notes[1]
    local base_sign = {
      name = discussion_sign_name,
      group = discussion_sign_name,
      priority = state.settings.discussion_sign.priority,
    }
    local base_helper_sign = {
      name = discussion_sign_name,
      group = discussion_sign_name,
      priority = state.settings.discussion_sign.priority - 1,
    }
    if first_note.position.line_range ~= nil then
      local start_old_line, start_new_line = _parse_line_code(first_note.position.line_range.start.line_code)
      local end_old_line, end_new_line = _parse_line_code(first_note.position.line_range["end"].line_code)
      local discussion_line, start_line, end_line
      if first_note.position.line_range.start.type == "new" then
        table.insert(
          new_signs,
          vim.tbl_deep_extend("force", {
            id = first_note.id,
            lnum = first_note.position.new_line,
          }, base_sign)
        )
        discussion_line = first_note.position.new_line
        start_line = start_new_line
        end_line = end_new_line
      elseif first_note.position.line_range.start.type == "old" then
        table.insert(
          old_signs,
          vim.tbl_deep_extend("force", {
            id = first_note.id,
            lnum = first_note.position.old_line,
          }, base_sign)
        )
        discussion_line = first_note.position.old_line
        start_line = start_old_line
        end_line = end_old_line
      end
      -- Helper signs does not have specific ids currently.
      if state.settings.discussion_sign.helper_signs.enabled then
        local helper_signs = {}
        if start_line > end_line then
          start_line, end_line = end_line, start_line
        end
        for i = start_line, end_line do
          if i ~= discussion_line then
            local sign_name
            if i == start_line then
              sign_name = discussion_helper_sign_start
            elseif i == end_line then
              sign_name = discussion_helper_sign_end
            else
              sign_name = discussion_helper_sign_mid
            end
            table.insert(
              helper_signs,
              vim.tbl_deep_extend("keep", {
                name = sign_name,
                lnum = i,
              }, base_helper_sign)
            )
          end
        end
        if first_note.position.line_range.start.type == "new" then
          vim.list_extend(new_signs, helper_signs)
        elseif first_note.position.line_range.start.type == "old" then
          vim.list_extend(old_signs, helper_signs)
        end
      end
    else
      local sign = vim.tbl_deep_extend("force", {
        id = first_note.id,
      }, base_sign)
      if first_note.position.new_line ~= nil then
        table.insert(new_signs, vim.tbl_deep_extend("force", { lnum = first_note.position.new_line }, sign))
      end
      if first_note.position.old_line ~= nil then
        table.insert(old_signs, vim.tbl_deep_extend("force", { lnum = first_note.position.old_line }, sign))
      end
    end
  end
  vim.fn.sign_unplace(discussion_sign_name)
  reviewer.place_sign(old_signs, "old")
  reviewer.place_sign(new_signs, "new")
end

---Refresh the diagnostics for the currently reviewed file
M.refresh_diagnostics = function(discussions)
  -- Keep in mind that diagnostic line numbers use 0-based indexing while line numbers use
  -- 1-based indexing
  local diagnostics = filter_discussions_for_signs_and_diagnostics(discussions)
  if diagnostics == nil then
    vim.diagnostic.reset(diagnostics_namespace)
    return
  end

  local new_diagnostics = {}
  local old_diagnostics = {}
  for _, discussion in ipairs(diagnostics) do
    local first_note = discussion.notes[1]
    local message = ""
    for _, note in ipairs(discussion.notes) do
      message = message .. build_note_header(note) .. "\n" .. note.body .. "\n"
    end

    local diagnostic = {
      message = message,
      col = 0,
      severity = state.settings.discussion_diagnostic.severity,
      user_data = { discussion_id = discussion.id, header = build_note_header(discussion.notes[1]) },
      source = "gitlab",
      code = state.settings.discussion_diagnostic.code,
    }
    if first_note.position.line_range ~= nil then
      -- Diagnostics for line range discussions are tricky - you need to set lnum to
      -- line number equal to note.position.new_line or note.position.old_line because that is
      -- only line where you can trigger the diagnostic show. This also need to be in sinc
      -- with the sign placement.
      local start_old_line, start_new_line = _parse_line_code(first_note.position.line_range.start.line_code)
      local end_old_line, end_new_line = _parse_line_code(first_note.position.line_range["end"].line_code)
      if first_note.position.line_range.start.type == "new" then
        local new_diagnostic
        if first_note.position.new_line == start_new_line then
          new_diagnostic = {
            lnum = start_new_line - 1,
            end_lnum = end_new_line - 1,
          }
        else
          new_diagnostic = {
            lnum = end_new_line - 1,
            end_lnum = start_new_line - 1,
          }
        end
        new_diagnostic = vim.tbl_deep_extend("force", new_diagnostic, diagnostic)
        table.insert(new_diagnostics, new_diagnostic)
      elseif first_note.position.line_range.start.type == "old" then
        local old_diagnostic
        if first_note.position.old_line == start_old_line then
          old_diagnostic = {
            lnum = start_old_line - 1,
            end_lnum = end_old_line - 1,
          }
        else
          old_diagnostic = {
            lnum = end_old_line - 1,
            end_lnum = start_old_line - 1,
          }
        end
        old_diagnostic = vim.tbl_deep_extend("force", old_diagnostic, diagnostic)
        table.insert(old_diagnostics, old_diagnostic)
      end
    else
      -- Diagnostics for single line discussions.
      if first_note.position.new_line ~= nil then
        local new_diagnostic = {
          lnum = first_note.position.new_line - 1,
        }
        new_diagnostic = vim.tbl_deep_extend("force", new_diagnostic, diagnostic)
        table.insert(new_diagnostics, new_diagnostic)
      end
      if first_note.position.old_line ~= nil then
        local old_diagnostic = {
          lnum = first_note.position.old_line - 1,
        }
        old_diagnostic = vim.tbl_deep_extend("force", old_diagnostic, diagnostic)
        table.insert(old_diagnostics, old_diagnostic)
      end
    end
  end

  vim.diagnostic.reset(diagnostics_namespace)
  reviewer.set_diagnostics(
    diagnostics_namespace,
    new_diagnostics,
    "new",
    state.settings.discussion_diagnostic.display_opts
  )
  reviewer.set_diagnostics(
    diagnostics_namespace,
    old_diagnostics,
    "old",
    state.settings.discussion_diagnostic.display_opts
  )
end

---Clear all signs and diagnostics
M.clear_signs_and_discussions = function()
  vim.fn.sign_unplace(discussion_sign_name)
  vim.diagnostic.reset(diagnostics_namespace)
end

return M
