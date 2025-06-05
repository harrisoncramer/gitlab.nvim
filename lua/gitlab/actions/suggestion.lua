---This module is responsible for previewing changes suggested in comments.
---The data required to make the API calls are drawn from the discussion nodes.

local common = require("gitlab.actions.common")
local git = require("gitlab.git")
local List = require("gitlab.utils.list")
local u = require("gitlab.utils")
local indicators_common = require("gitlab.indicators.common")

local M = {}

vim.fn.sign_define("GitlabSuggestion", {
  text = "+",
  texthl = "WarningMsg",
})

local suggestion_namespace = vim.api.nvim_create_namespace("gitlab_suggestion_note")

---Reset the contents of the suggestion buffer
---@param bufnr integer
---@param lines string[]
local set_buffer_lines = function(bufnr, lines)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  if M.imply_local then
    vim.api.nvim_buf_call(bufnr, function()
      vim.api.nvim_cmd({ cmd = "write", mods = { silent = true } }, {})
    end)
  end
end

---Set keymaps for the suggestion tab buffers
---@param note_buf integer Number of the note buffer
---@param original_buf integer Number of the buffer with the original contents of the file
---@param suggestion_buf integer Number of the buffer with applied suggestions (can be local or scratch)
---@param original_lines string[] The list of lines in the original (commented on) version of the file
---@param root_node NuiTreeNode The first comment in the discussion thread (can be a draft comment)
---@param note_node NuiTreeNode The first node of a comment or reply
local set_keymaps = function(note_buf, original_buf, suggestion_buf, original_lines, root_node, note_node)
  local keymaps = require("gitlab.state").settings.keymaps

  -- Reset suggestion buffer to original state and close preview tab
  for _, bufnr in ipairs({ note_buf, original_buf, suggestion_buf }) do
    vim.keymap.set("n", keymaps.popup.discard_changes, function()
      set_buffer_lines(suggestion_buf, original_lines)
      if vim.api.nvim_buf_is_valid(note_buf) then
        vim.bo[note_buf].modified = false
      end
      vim.cmd.tabclose()
    end, { buffer = bufnr, desc = "Close preview tab discarding changes" })
  end

  -- Post updated suggestion note buffer to the server.
  vim.keymap.set("n", keymaps.popup.perform_action, function()
    vim.api.nvim_buf_call(note_buf, function()
      vim.api.nvim_cmd({ cmd = "write", mods = { silent = true } }, {})
    end)
    local note_id = note_node.is_root and note_node.root_note_id or note_node.id
    local edit_action = root_node.is_draft
        and require("gitlab.actions.draft_notes").confirm_edit_draft_note(note_id, false)
      or require("gitlab.actions.comment").confirm_edit_comment(root_node.id, note_id, false)
    edit_action(u.get_buffer_text(note_buf))
    set_buffer_lines(suggestion_buf, original_lines)
    vim.cmd.tabclose()
  end, { buffer = note_buf, desc = "Update suggestion note on Gitlab" })
end

local replace_range = function(full_text, start_idx, end_idx, new_lines)
  -- Copy the original text
  local new_tbl = {}
  for _, val in ipairs(full_text) do
    table.insert(new_tbl, val)
  end
  -- Remove old lines
  for _ = start_idx, end_idx do
    table.remove(new_tbl, start_idx)
  end
  -- Insert new lines
  for i, line in ipairs(new_lines) do
    table.insert(new_tbl, start_idx + i - 1, line)
  end
  return new_tbl
end

local refresh_signs = function(suggestion, note_buf)
  vim.fn.sign_unplace("gitlab.suggestion")

  vim.fn.sign_place(
    suggestion.note_start_linenr,
    "gitlab.suggestion",
    "GitlabSuggestion",
    note_buf,
    { lnum = suggestion.note_start_linenr }
  )
  vim.fn.sign_place(
    suggestion.note_end_linenr,
    "gitlab.suggestion",
    "GitlabSuggestion",
    note_buf,
    { lnum = suggestion.note_end_linenr }
  )
end

local get_temp_file_name = function(revision, node_id, file_name)
  local buf_name = string.format("gitlab://%s/%s/%s", revision, node_id, file_name)
  local existing_bufnr = vim.fn.bufnr(buf_name)
  if existing_bufnr > -1 and vim.fn.bufexists(existing_bufnr) then
    vim.cmd.bwipeout(existing_bufnr)
  end
  return buf_name
end

---Check if buffer already exists and return the number of the tab it's open in
---@param bufname string The full name of the buffer to check.
---@return number|nil tabnr The tabpage number if buffer is already open or nil.
local get_tabnr_for_buf = function(bufname)
  local bufnr = vim.fn.bufnr(bufname)
  if bufnr == -1 then
    return nil
  end
  for _, tabnr in ipairs(vim.api.nvim_list_tabpages()) do
    for _, winnr in ipairs(vim.api.nvim_tabpage_list_wins(tabnr)) do
      if vim.api.nvim_win_get_buf(winnr) == bufnr then
        return tabnr
      end
    end
  end
  return nil
end

---@class Suggestion
---@field start_line_offset number The offset for the start of the suggestion (e.g., "2" in suggestion:-2+3)
---@field end_line_offset number The offset for the end of the suggestion (e.g., "3" in suggestion:-2+3)
---@field note_start_linenr number The line number in the note text where the suggesion begins
---@field note_end_linenr number The line number in the note text where the suggesion ends
---@field lines string[] The text of the suggesion
---@field full_text string[] The full text of the file with the suggesion applied

---Create the suggestion list from the note text
---@return Suggestion[]
local get_suggestions = function(note_lines)
  local suggestions = {}
  local in_suggestion = false
  local suggestion = {}
  local quote

  for i, line in ipairs(note_lines) do
    local start_quote = string.match(line, "^%s*(`+)suggestion:%-%d+%+%d+")
    local end_quote = string.match(line, "^%s*(`+)%s*$")

    if start_quote ~= nil and not in_suggestion then
      quote = start_quote
      in_suggestion = true
      suggestion.start_line_offset, suggestion.end_line_offset = string.match(line, "^%s*`+suggestion:%-(%d+)%+(%d+)")
      suggestion.note_start_linenr = i
      suggestion.lines = {}
    elseif end_quote and end_quote == quote then
      suggestion.note_end_linenr = i
      table.insert(suggestions, suggestion)
      in_suggestion = false
      suggestion = {}
    elseif in_suggestion then
      table.insert(suggestion.lines, line)
    end
  end
  return suggestions
end

---Create diagnostics data from suggesions
---@param suggestions Suggestion[]
local create_diagnostics = function(suggestions)
  local diagnostics_data = {}
  for _, suggestion in ipairs(suggestions) do
    local diagnostic = {
      message = table.concat(suggestion.lines, "\n") .. "\n",
      col = 0,
      severity = vim.diagnostic.severity.INFO,
      source = "gitlab",
      code = "gitlab.nvim",
      lnum = suggestion.note_start_linenr - 1,
    }
    table.insert(diagnostics_data, diagnostic)
  end
  return diagnostics_data
end

---Show diagnostics for suggestions (enables using built-in navigation)
---@param suggestions Suggestion[] The list of suggestions for which diagnostics should be created.
---@param note_buf integer The number of the note buffer
local refresh_diagnostics = function(suggestions, note_buf)
  local diagnostics_data = create_diagnostics(suggestions)
  vim.diagnostic.reset(suggestion_namespace, note_buf)
  vim.diagnostic.set(suggestion_namespace, note_buf, diagnostics_data, indicators_common.create_display_opts())
end

---Return true if the file has uncommitted or unsaved changes.
---@param file_name string Name of file to check.
---@return boolean
local is_modified = function(file_name)
  local has_changes = git.has_changes(file_name)
  local bufnr = vim.fn.bufnr(file_name, true)
  if vim.bo[bufnr].modified or has_changes then
    return true
  end
  return false
end

---Update suggestions with the changes applied to the original text
---@param suggestions Suggestion[]
---@param end_line_number integer The last number of the comment range
---@param original_lines string[] Array of original lines
local add_full_text_to_suggestions = function(suggestions, end_line_number, original_lines)
  for _, suggestion in ipairs(suggestions) do
    local start_line = end_line_number - suggestion.start_line_offset
    local end_line = end_line_number + suggestion.end_line_offset
    suggestion.full_text = replace_range(original_lines, start_line, end_line, suggestion.lines)
  end
end

---Create autocommands for the note buffer
---@param note_buf integer Note buffer number
---@param suggestion_buf integer Suggestion buffer number
---@param suggestions Suggestion[]
---@param end_line_number integer The last number of the comment range
---@param original_lines string[] Array of original lines
local create_autocommands = function(note_buf, suggestion_buf, suggestions, end_line_number, original_lines)
  -- Create autocommand for showing the active suggestion buffer in window 2
  local last_line = suggestions[1].note_start_linenr
  local last_suggestion = suggestions[1]
  vim.api.nvim_create_autocmd({ "CursorMoved" }, {
    buffer = note_buf,
    callback = function()
      local current_line = vim.fn.line(".")
      if current_line ~= last_line then
        local suggestion = List.new(suggestions):find(function(sug)
          return current_line <= sug.note_end_linenr
        end)
        if suggestion and suggestion ~= last_suggestion then
          set_buffer_lines(suggestion_buf, suggestion.full_text)
          last_line = current_line
          last_suggestion = suggestion
          refresh_signs(suggestion, note_buf)
        end
      end
    end,
  })

  -- Create autocommand to update suggestions list based on the note buffer content.
  vim.api.nvim_create_autocmd({ "BufWritePost" }, {
    buffer = note_buf,
    callback = function()
      local updated_note_lines = vim.api.nvim_buf_get_lines(note_buf, 0, -1, false)
      suggestions = get_suggestions(updated_note_lines)
      add_full_text_to_suggestions(suggestions, end_line_number, original_lines)
      last_line = 0
      vim.api.nvim_exec_autocmds("CursorMoved", { buffer = note_buf })
      refresh_diagnostics(suggestions, note_buf)
    end,
  })
end

---Show the note header as virtual text
---@param text string The text to show in the header
---@param note_buf integer The number of the note buffer
local add_window_header = function(text, note_buf)
  local mark_opts = {
    virt_lines = { { { text, "WarningMsg" } } },
    virt_lines_above = true,
    right_gravity = false,
  }
  vim.api.nvim_buf_set_extmark(note_buf, suggestion_namespace, 0, 0, mark_opts)
  -- An extmark above the first line is not visible by default, so let's scroll the window:
  vim.cmd("normal! ")
  -- TODO: Add virtual text (or winbar?) to show the diffed revision of the ORIGINAL.
end

---Get suggestions from the current note and preview them in a new tab
---@param tree NuiTree The current discussion tree instance
M.show_preview = function(tree)
  local current_node = tree:get_node()
  local root_node = common.get_root_node(tree, current_node)
  local note_node = common.get_note_node(tree, current_node)
  if root_node == nil or note_node == nil then
    u.notify("Couldn't get root node or note node", vim.log.levels.ERROR)
    return
  end

  -- -- If preview is already open for given note, go to the tab with a warning.
  -- -- TODO: fix checking that note is already being edited.
  -- local note_bufname = string.format("gitlab://NOTE/%s", root_node._id)
  -- local tabnr = get_tabnr_for_buf(note_bufname)
  -- if tabnr ~= nil then
  --   vim.api.nvim_set_current_tabpage(tabnr)
  --   u.notify("Previously created preview can be outdated", vim.log.levels.WARN)
  --   return
  -- end

  -- Return early when there're no suggestions.
  local note_lines = common.get_note_lines(tree)
  local suggestions = get_suggestions(note_lines)
  if #suggestions == 0 then
    u.notify("Note doesn't contain any suggestion.", vim.log.levels.WARN)
    return
  end

  -- Hack: draft notes don't have head_sha and base_sha yet
  if root_node.is_draft then
    root_node.head_sha = "HEAD"
    root_node.base_sha = require("gitlab.state").INFO.target_branch
  end

  -- Decide which revision to use for the ORIGINAL text
  local _, is_new_sha, end_line_number = common.get_line_number_from_node(root_node)
  local revision, original_file_name
  if is_new_sha then
    revision = root_node.head_sha
    original_file_name = root_node.file_name
  else
    revision = root_node.base_sha
    original_file_name = root_node.old_file_name
  end
  if not git.revision_exists(revision) then
    u.notify(
      string.format("Revision `%s` for which the comment was made does not exist", revision),
      vim.log.levels.WARN
    )
    return
  end

  -- Get the text on which the suggestion was created
  local original_head_text = git.get_file_revision({ file_name = original_file_name, revision = revision })
  -- If the original revision doesn't contain the file, the branch was possibly rebased, and the
  -- original revision could not been found.
  if original_head_text == nil then
    u.notify(
      string.format(
        "File `%s` doesn't contain any text in revision `%s` for which comment was made",
        original_file_name,
        revision
      ),
      vim.log.levels.WARN
    )
    return
  end
  local original_lines = vim.fn.split(original_head_text, "\n", true)

  add_full_text_to_suggestions(suggestions, end_line_number, original_lines)

  -- Create new tab with a temp buffer showing the original version on which the comment was
  -- made.
  local original_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(original_buf, 0, -1, false, original_lines)
  local buf_name = get_temp_file_name("ORIGINAL", root_node._id, root_node.file_name)
  vim.api.nvim_buf_set_name(original_buf, buf_name)
  vim.api.nvim_cmd({ cmd = "tabnew", args = { buf_name } }, {})
  vim.bo.bufhidden = "wipe"
  vim.bo.buflisted = false
  vim.bo.buftype = "nofile"
  vim.bo.modifiable = false
  vim.cmd.filetype("detect")
  local buf_filetype = vim.api.nvim_get_option_value("filetype", { buf = 0 })

  -- Decide if local file should be used to show suggestion preview
  local head_differs_from_original = git.file_differs_in_revisions({
    original_revision = revision,
    head_revision = "HEAD",
    old_file_name = root_node.old_file_name,
    file_name = root_node.file_name,
  })
  M.imply_local = false
  if not is_new_sha then
    u.notify(
      string.format("Comment on unchanged text. Using target-branch version of `%s`", original_file_name),
      vim.log.levels.WARNING
    )
  elseif head_differs_from_original then
    u.notify(
      string.format("File changed since comment created. Using feature-branch version of `%s`", original_file_name),
      vim.log.levels.WARNING
    )
  elseif is_modified(original_file_name) then
    u.notify(
      string.format("File has unsaved or uncommited changes. Using feature-branch version for `%s`", original_file_name),
      vim.log.levels.WARNING
    )
  else
    M.imply_local = true
  end

  -- Create the suggestion buffer and show a diff with the original version
  local split_cmd = vim.o.columns > 240 and "vsplit" or "split"
  if M.imply_local then
    vim.api.nvim_cmd({ cmd = split_cmd, args = { original_file_name } }, {})
  else
    local sug_file_name = get_temp_file_name("SUGGESTION", root_node._id, root_node.file_name)
    vim.fn.mkdir(vim.fn.fnamemodify(sug_file_name, ":h"), "p")
    vim.api.nvim_cmd({ cmd = split_cmd, args = { sug_file_name } }, {})
    vim.bo.bufhidden = "wipe"
    vim.bo.buflisted = false
    vim.bo.buftype = "nofile"
    vim.bo.filetype = buf_filetype
  end
  local suggestion_buf = vim.api.nvim_get_current_buf()
  set_buffer_lines(suggestion_buf, suggestions[1].full_text)
  vim.cmd("1,2windo diffthis")

  -- Create the note window
  local note_buf = vim.api.nvim_create_buf(false, false)
  local note_bufname = vim.fn.tempname()
  vim.api.nvim_buf_set_name(note_buf, note_bufname)
  vim.api.nvim_cmd({ cmd = "vnew", mods = { split = "botright" }, args = { note_bufname } }, {})
  vim.api.nvim_buf_set_lines(note_buf, 0, -1, false, note_lines)
  vim.bo.bufhidden = "wipe"
  vim.bo.buflisted = false
  vim.bo.filetype = "markdown"
  vim.bo.modified = false

  -- Focus the note window
  local note_winid = vim.fn.win_getid(3)
  vim.api.nvim_win_set_cursor(note_winid, { suggestions[1].note_start_linenr, 0 })
  refresh_signs(suggestions[1], note_buf)
  set_keymaps(note_buf, original_buf, suggestion_buf, original_lines, root_node, note_node)
  refresh_diagnostics(suggestions, note_buf)
  create_autocommands(note_buf, suggestion_buf, suggestions, end_line_number, original_lines)
  add_window_header(note_node.text, note_buf)
end

return M
