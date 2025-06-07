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

---Reset the contents of the suggestion buffer.
---@param bufnr integer The number of the suggestion buffer.
---@param lines string[] Lines of text to put into the buffer.
---@param imply_local boolean True if buffer is local file and should be written.
local set_buffer_lines = function(bufnr, lines, imply_local)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  if imply_local then
    vim.api.nvim_buf_call(bufnr, function()
      vim.api.nvim_cmd({ cmd = "write", mods = { silent = true } }, {})
    end)
  end
end

---Set keymaps for the suggestion tab buffers.
---@param note_buf integer Number of the note buffer.
---@param original_buf integer Number of the buffer with the original contents of the file.
---@param suggestion_buf integer Number of the buffer with applied suggestions (can be local or scratch).
---@param original_lines string[] The list of lines in the original (commented on) version of the file.
---@param root_node NuiTreeNode The first comment in the discussion thread (can be a draft comment).
---@param note_node NuiTreeNode The first node of a comment or reply.
---@param imply_local boolean True if suggestion buffer is local file and should be written.
local set_keymaps = function(note_buf, original_buf, suggestion_buf, original_lines, root_node, note_node, imply_local)
  local keymaps = require("gitlab.state").settings.keymaps

  -- Reset suggestion buffer to original state and close preview tab
  if keymaps.suggestion_preview.discard_changes then
    for _, bufnr in ipairs({ note_buf, original_buf, suggestion_buf }) do
      vim.keymap.set("n", keymaps.suggestion_preview.discard_changes, function()
        set_buffer_lines(suggestion_buf, original_lines, imply_local)
        if vim.api.nvim_buf_is_valid(note_buf) then
          vim.bo[note_buf].modified = false
        end
        vim.cmd.tabclose()
      end, { buffer = bufnr, desc = "Close preview tab discarding changes", nowait = keymaps.suggestion_preview.discard_changes_nowait })
    end
  end

  -- Post updated suggestion note buffer to the server.
  if keymaps.suggestion_preview.apply_changes then
    vim.keymap.set("n", keymaps.suggestion_preview.apply_changes, function()
      vim.api.nvim_buf_call(note_buf, function()
        vim.api.nvim_cmd({ cmd = "write", mods = { silent = true } }, {})
      end)
      local note_id = tonumber(note_node.is_root and note_node.root_note_id or note_node.id)
      local edit_action = root_node.is_draft
          and require("gitlab.actions.draft_notes").confirm_edit_draft_note(note_id, false)
        or require("gitlab.actions.comment").confirm_edit_comment(root_node.id, note_id, false)
      edit_action(u.get_buffer_text(note_buf))
      set_buffer_lines(suggestion_buf, original_lines, imply_local)
      vim.cmd.tabclose()
    end, { buffer = note_buf, desc = "Update suggestion note on Gitlab", nowait = keymaps.suggestion_preview.apply_changes_nowait  })
  end
end

---Replace a range of items in a list with items from another list.
---@param full_text string[] The full list of lines.
---@param start_idx integer The beginning of the range to be replaced.
---@param end_idx integer The end of the range to be replaced.
---@param new_lines string[] The lines of text that should replace the original range.
---@param note_start_linenr number The line number in the note text where the suggesion begins
---@return string[] new_tbl The new list of lines after replacing.
local replace_line_range = function(full_text, start_idx, end_idx, new_lines, note_start_linenr)
  if start_idx < 1 then
    u.notify(string.format("Can't apply suggestion at line %d, invalid start of range.", note_start_linenr), vim.log.levels.ERROR)
    return full_text
  end
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

---Refresh the signs in the note buffer.
---@param suggestion Suggestion The data for an individual suggestion.
---@param note_buf integer The number of the note buffer.
local refresh_signs = function(suggestion, note_buf)
  vim.fn.sign_unplace("gitlab.suggestion")
  if suggestion.is_default then
    return
  end
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

---Create the name for a temporary file.
---@param revision string The revision of the file for which the comment was made.
---@param node_id any The id of the note node containing the suggestion.
---@param file_name string The name of the commented file.
---@return string buf_name The full name of the new buffer.
---@return integer bufnr The number of the buffer associated with the new name (-1 if buffer doesn't exist).
local get_temp_file_name = function(revision, node_id, file_name)
  local buf_name = string.format("gitlab::%s/%s::%s", revision, node_id, file_name)
  local bufnr = vim.fn.bufnr(buf_name)
  return buf_name, bufnr
end

---Get the text on which the suggestion was created.
---@param original_file_name string The name of the file on which the comment was made.
---@param revision string The revision of the file for which the comment was made.
---@return string[]|nil original_lines The list of original lines.
local get_original_lines = function(original_file_name, revision)
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
  return vim.fn.split(original_head_text, "\n", true)
end

---Check if buffer already exists and return the number of the tab it's open in.
---@param bufnr integer The buffer number to check.
---@return number|nil tabnr The tabpage number if buffer is already open, or nil.
local get_tabnr_for_buf = function(bufnr)
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
---@field is_default boolean If true, the "suggestion" is a placeholder for comments without actual suggestions.

---Create the suggestion list from the note text.
---@param note_lines string[] The content of the comment.
---@param end_line_number integer The last number of the comment range.
---@param original_lines string[] Array of original lines.
---@return Suggestion[] suggestions List of suggestion data.
local get_suggestions = function(note_lines, end_line_number, original_lines)
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
    elseif in_suggestion and end_quote and end_quote == quote then
      suggestion.note_end_linenr = i

      -- Add the full text with the changes applied to the original text.
      local start_line = end_line_number - suggestion.start_line_offset
      local end_line = end_line_number + suggestion.end_line_offset
      suggestion.full_text = replace_line_range(original_lines, start_line, end_line, suggestion.lines, suggestion.note_start_linenr)

      table.insert(suggestions, suggestion)
      in_suggestion = false
      suggestion = {}
    elseif in_suggestion then
      table.insert(suggestion.lines, line)
    end
  end

  if #suggestions == 0 then
    suggestions = {
      {
        start_line_offset = 0,
        end_line_offset = 0,
        note_start_linenr = 1,
        note_end_linenr = 1,
        lines = {},
        full_text = original_lines,
        is_default = true,
      }
    }
  end
  return suggestions
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

---Decide if local file should be used to show suggestion preview
---@param revision string The revision of the file for which the comment was made.
---@param root_node NuiTreeNode The first comment in the discussion thread (can be a draft comment).
---@param is_new_sha boolean True if line number refers to NEW SHA
---@param original_file_name string The name of the file on which the comment was made.
local determine_imply_local = function(revision, root_node, is_new_sha, original_file_name)
  local head_differs_from_original = git.file_differs_in_revisions({
    original_revision = revision,
    head_revision = "HEAD",
    old_file_name = root_node.old_file_name,
    file_name = root_node.file_name,
  })
  if not is_new_sha then
    u.notify(
      string.format("Comment on unchanged text. Using target-branch version of `%s`", original_file_name),
      vim.log.levels.INFO
    )
  elseif head_differs_from_original then
    u.notify(
      string.format("File changed since comment created. Using feature-branch version of `%s`", original_file_name),
      vim.log.levels.INFO
    )
  elseif is_modified(original_file_name) then
    u.notify(
      string.format("File has unsaved or uncommited changes. Using feature-branch version for `%s`", original_file_name),
      vim.log.levels.WARN
    )
  else
    return true
  end
  return false
end

---Create diagnostics data from suggesions.
---@param suggestions Suggestion[] The list of suggestions data for the current note.
---@return vim.Diagnostic[] diagnostics_data List of diagnostic data for vim.diagnostic.set.
local create_diagnostics = function(suggestions)
  local diagnostics_data = {}
  for _, suggestion in ipairs(suggestions) do
    if not suggestion.is_default then
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
  end
  return diagnostics_data
end

---Show diagnostics for suggestions (enables using built-in navigation with `]d` and `[d`).
---@param suggestions Suggestion[] The list of suggestions for which diagnostics should be created.
---@param note_buf integer The number of the note buffer
local refresh_diagnostics = function(suggestions, note_buf)
  local diagnostics_data = create_diagnostics(suggestions)
  vim.diagnostic.reset(suggestion_namespace, note_buf)
  vim.diagnostic.set(suggestion_namespace, note_buf, diagnostics_data, indicators_common.create_display_opts())
end

---Create autocommands for the note buffer.
---@param note_buf integer Note buffer number.
---@param suggestion_buf integer Suggestion buffer number.
---@param suggestions Suggestion[] List of suggestion data.
---@param end_line_number integer The last number of the comment range.
---@param original_lines string[] Array of original lines.
---@param imply_local boolean True if suggestion buffer is local file and should be written.
local create_autocommands = function(note_buf, suggestion_buf, suggestions, end_line_number, original_lines, imply_local)
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
          set_buffer_lines(suggestion_buf, suggestion.full_text, imply_local)
          last_line = current_line
          last_suggestion = suggestion
          refresh_signs(suggestion, note_buf)
        end
      end
    end,
  })

  -- Create autocommand to update suggestions list based on the note buffer content.
  -- vim.api.nvim_create_autocmd({ "BufWritePost", "CursorHold", "CursorHoldI"  }, {
  vim.api.nvim_create_autocmd({ "BufWritePost", }, {
    buffer = note_buf,
    callback = function()
      local updated_note_lines = vim.api.nvim_buf_get_lines(note_buf, 0, -1, false)
      suggestions = get_suggestions(updated_note_lines, end_line_number, original_lines)
      last_line = 0
      vim.api.nvim_exec_autocmds("CursorMoved", { buffer = note_buf })
      refresh_diagnostics(suggestions, note_buf)
    end,
  })
end

---Show the note header as virtual text.
---@param text string The text to show in the header.
---@param note_buf integer The number of the note buffer.
local add_window_header = function(text, note_buf)
  local mark_opts = {
    virt_lines = { { { text, "WarningMsg" } } },
    virt_lines_above = true,
    right_gravity = false,
  }
  vim.api.nvim_buf_set_extmark(note_buf, suggestion_namespace, 0, 0, mark_opts)
  -- An extmark above the first line is not visible by default, so let's scroll the window:
  vim.cmd("normal! ")
  -- TODO: Add virtual text (or winbar?) to show the diffed revision of the ORIGINAL. This doesn't
  -- work well because of the diff scrollbind makes the extmark above line 1 disappear.
end

---Get suggestions from the current note and preview them in a new tab.
---@param tree NuiTree The current discussion tree instance.
M.show_preview = function(tree)
  local current_node = tree:get_node()
  local root_node = common.get_root_node(tree, current_node)
  local note_node = common.get_note_node(tree, current_node)
  if root_node == nil or note_node == nil then
    u.notify("Couldn't get root node or note node", vim.log.levels.ERROR)
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

  -- If preview is already open for given note, go to the tab with a warning.
  local original_buf_name, original_bufnr = get_temp_file_name("ORIGINAL", note_node.id, original_file_name)
  local tabnr = get_tabnr_for_buf(original_bufnr)
  if tabnr ~= nil then
    vim.api.nvim_set_current_tabpage(tabnr)
    u.notify("Previously created preview can be outdated", vim.log.levels.WARN)
    return
  end

  local original_lines = get_original_lines(original_file_name, revision)
  if original_lines == nil then
    return
  end

  -- Return early when there're no suggestions.
  local note_lines = common.get_note_lines(tree)
  local suggestions = get_suggestions(note_lines, end_line_number, original_lines)

  -- Create new tab with a temp buffer showing the original version on which the comment was
  -- made.
  vim.fn.mkdir(vim.fn.fnamemodify(original_buf_name, ":h"), "p")
  vim.api.nvim_cmd({ cmd = "tabnew", args = { original_buf_name } }, {})
  local original_buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(original_buf, 0, -1, false, original_lines)
  vim.bo.bufhidden = "wipe"
  vim.bo.buflisted = false
  vim.bo.buftype = "nofile"
  vim.bo.modifiable = false
  vim.cmd.filetype("detect")
  local buf_filetype = vim.api.nvim_get_option_value("filetype", { buf = 0 })

  local imply_local = determine_imply_local(revision, root_node, is_new_sha, original_file_name)

  -- Create the suggestion buffer and show a diff with the original version
  local split_cmd = vim.o.columns > 240 and "vsplit" or "split"
  if imply_local then
    vim.api.nvim_cmd({ cmd = split_cmd, args = { original_file_name } }, {})
  else
    local sug_buf_name = get_temp_file_name("SUGGESTION", note_node.id, root_node.file_name)
    vim.fn.mkdir(vim.fn.fnamemodify(sug_buf_name, ":h"), "p")
    vim.api.nvim_cmd({ cmd = split_cmd, args = { sug_buf_name } }, {})
    vim.bo.bufhidden = "wipe"
    vim.bo.buflisted = false
    vim.bo.buftype = "nofile"
    vim.bo.filetype = buf_filetype
  end
  local suggestion_buf = vim.api.nvim_get_current_buf()
  set_buffer_lines(suggestion_buf, suggestions[1].full_text, imply_local)
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

  -- Set up keymaps and autocommands
  set_keymaps(note_buf, original_buf, suggestion_buf, original_lines, root_node, note_node, imply_local)
  create_autocommands(note_buf, suggestion_buf, suggestions, end_line_number, original_lines, imply_local)

  -- Focus the note window on the first suggestion
  local note_winid = vim.fn.win_getid(3)
  vim.api.nvim_win_set_cursor(note_winid, { suggestions[1].note_start_linenr, 0 })
  refresh_signs(suggestions[1], note_buf)
  refresh_diagnostics(suggestions, note_buf)
  add_window_header(note_node.text, note_buf)
end

return M
