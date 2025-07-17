---This module is responsible for previewing changes suggested in comments.
---The data required to make the API calls are drawn from the discussion nodes.

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

---Refresh the diagnostics from LSP in the suggestions buffer if there are any clients that support
---diagnostics.
---@param suggestion_buf integer Number of the buffer with applied suggestions (can be local or scratch).
local refresh_lsp_diagnostics = function(suggestion_buf)
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = suggestion_buf })) do
    if client:supports_method("textDocument/diagnostic", suggestion_buf) then
      vim.lsp.buf_request(suggestion_buf, "textDocument/diagnostic", {
        textDocument = vim.lsp.util.make_text_document_params(suggestion_buf),
      })
    end
  end
end

---Reset the contents of the suggestion buffer.
---@param bufnr integer The number of the suggestion buffer.
---@param lines string[] Lines of text to put into the buffer.
---@param imply_local boolean True if buffer is local file and should be written.
local set_buffer_lines = function(bufnr, lines, imply_local)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

  -- Recompute and re-apply folds (Otherwise folds are messed up when TextChangedI is triggered).
  -- TODO: Find out if it's a (Neo)vim bug.
  vim.api.nvim_buf_call(bufnr, function()
    vim.cmd("normal! zX")
  end)

  if imply_local then
    vim.api.nvim_buf_call(bufnr, function()
      vim.api.nvim_cmd({ cmd = "write", mods = { silent = true } }, {})
    end)
    refresh_lsp_diagnostics(bufnr)
  end
end

---Reset suggestion buffer options and keymaps before closing the preview.
---@param imply_local boolean True if suggestion buffer is local file and should be written.
---@param suggestion_buf integer Suggestion buffer number.
---@param original_lines string[] The list of lines in the original (commented on) version of the file.
---@param original_suggestion_winbar string The original suggestion buffer/window 'winbar'.
---@param suggestion_winid integer Suggestion window number in the preview tab.
local reset_suggestion_buf = function(
  imply_local,
  suggestion_buf,
  original_lines,
  original_suggestion_winbar,
  suggestion_winid
)
  local keymaps = require("gitlab.state").settings.keymaps
  set_buffer_lines(suggestion_buf, original_lines, imply_local)
  if imply_local then
    pcall(vim.api.nvim_buf_del_keymap, suggestion_buf, "n", keymaps.suggestion_preview.discard_changes)
    vim.api.nvim_set_option_value("winbar", original_suggestion_winbar, { scope = "local", win = suggestion_winid })
  end
end

---Set keymaps for the suggestion tab buffers.
---@param note_buf integer Number of the note buffer.
---@param original_buf integer Number of the buffer with the original contents of the file.
---@param suggestion_buf integer Number of the buffer with applied suggestions (can be local or scratch).
---@param original_lines string[] The list of lines in the original (commented on) version of the file.
---@param imply_local boolean True if suggestion buffer is local file and should be written.
---@param default_suggestion_lines string[] The default suggestion lines with backticks.
---@param original_suggestion_winbar string The original suggestion buffer/window 'winbar'.
---@param suggestion_winid integer Suggestion window number in the preview tab.
---@param opts ShowPreviewOpts The options passed to the M.show_preview function.
local set_keymaps = function(
  note_buf,
  original_buf,
  suggestion_buf,
  original_lines,
  imply_local,
  default_suggestion_lines,
  original_suggestion_winbar,
  suggestion_winid,
  opts
)
  local keymaps = require("gitlab.state").settings.keymaps

  for _, bufnr in ipairs({ note_buf, original_buf, suggestion_buf }) do
    -- Reset suggestion buffer to original state and close preview tab
    if keymaps.suggestion_preview.discard_changes then
      vim.keymap.set("n", keymaps.suggestion_preview.discard_changes, function()
        if vim.api.nvim_buf_is_valid(note_buf) then
          vim.bo[note_buf].modified = false
        end
        -- Resetting can cause invalid-buffer errors for temporary (non-local) suggestion buffer
        if imply_local then
          reset_suggestion_buf(
            imply_local,
            suggestion_buf,
            original_lines,
            original_suggestion_winbar,
            suggestion_winid
          )
        end
        vim.cmd.tabclose()
      end, {
        buffer = bufnr,
        desc = "Close preview tab discarding changes",
        nowait = keymaps.suggestion_preview.discard_changes_nowait,
      })
    end

    if keymaps.help then
      vim.keymap.set("n", keymaps.help, function()
        local help = require("gitlab.actions.help")
        help.open()
      end, { buffer = bufnr, desc = "Open help", nowait = keymaps.help_nowait })
    end
  end

  -- Post updated suggestion note buffer to the server.
  if keymaps.suggestion_preview.apply_changes then
    vim.keymap.set("n", keymaps.suggestion_preview.apply_changes, function()
      vim.api.nvim_buf_call(note_buf, function()
        vim.api.nvim_cmd({ cmd = "write", mods = { silent = true } }, {})
      end)

      local buf_text = u.get_buffer_text(note_buf)
      if opts.comment_type == "reply" then
        require("gitlab.actions.comment").confirm_create_comment(buf_text, false, opts.root_node_id)
      elseif opts.comment_type == "draft" then
        require("gitlab.actions.draft_notes").confirm_edit_draft_note(opts.note_node_id, false)(buf_text)
      elseif opts.comment_type == "edit" then
        require("gitlab.actions.comment").confirm_edit_comment(opts.root_node_id, opts.note_node_id, false)(buf_text)
      elseif opts.comment_type == "new" then
        require("gitlab.actions.comment").confirm_create_comment(buf_text, false)
      elseif opts.comment_type == "apply" then
        if imply_local then
          -- Override original with current buffer contents
          original_lines = vim.api.nvim_buf_get_lines(suggestion_buf, 0, -1, false)
        else
          u.notify("Cannot apply temp-file preview to local file.", vim.log.levels.ERROR)
        end
      else
        -- This should not really happen.
        u.notify(string.format("Cannot perform unsupported action `%s`", opts.comment_type), vim.log.levels.ERROR)
      end

      reset_suggestion_buf(imply_local, suggestion_buf, original_lines, original_suggestion_winbar, suggestion_winid)
      vim.cmd.tabclose()
    end, {
      buffer = note_buf,
      desc = opts.comment_type == "apply" and "Write changes to local file" or "Post suggestion comment to Gitlab",
      nowait = keymaps.suggestion_preview.apply_changes_nowait,
    })
  end

  if keymaps.suggestion_preview.paste_default_suggestion then
    vim.keymap.set("n", keymaps.suggestion_preview.paste_default_suggestion, function()
      vim.api.nvim_put(default_suggestion_lines, "l", true, false)
    end, {
      buffer = note_buf,
      desc = "Paste default suggestion",
      nowait = keymaps.suggestion_preview.paste_default_suggestion_nowait,
    })
  end

  -- TODO: Keymap for uploading files.
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
    u.notify(
      string.format("Can't apply suggestion at line %d, invalid start of range.", note_start_linenr),
      vim.log.levels.ERROR
    )
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
---@param node_id string|integer The id of the note node containing the suggestion.
---@param file_name string The name of the commented file.
---@return string buf_name The full name of the new buffer.
---@return integer bufnr The number of the buffer associated with the new name (-1 if buffer doesn't exist).
local get_temp_file_name = function(revision, node_id, file_name)
  -- TODO: Come up with a nicer naming convention.
  local buf_name = string.format("gitlab::%s/%s::%s", revision, node_id, file_name)
  local bufnr = vim.fn.bufnr(buf_name)
  return buf_name, bufnr
end

---Get the text on which the suggestion was created.
---@param opts ShowPreviewOpts The options passed to the M.show_preview function.
---@return string[]|nil original_lines The list of original lines.
local get_original_lines = function(opts)
  local original_head_text = git.get_file_revision({
    file_name = opts.is_new_sha and opts.new_file_name or opts.old_file_name,
    revision = opts.revision,
  })
  -- If the original revision doesn't contain the file, the branch was possibly rebased, and the
  -- original revision could not been found.
  if original_head_text == nil then
    u.notify(
      string.format(
        "File `%s` doesn't contain any text in revision `%s` for which comment was made",
        opts.old_file_name,
        opts.revision
      ),
      vim.log.levels.WARN
    )
    return
  end
  return vim.fn.split(original_head_text, "\n", true)
end

---Create the default suggestion lines for given comment range.
---@param original_lines string[] The list of lines in the original (commented on) version of the file.
---@param opts ShowPreviewOpts The options passed to the M.show_preview function.
---@return string[] suggestion_lines
local get_default_suggestion = function(original_lines, opts)
  local backticks = "```"
  local selected_lines = { unpack(original_lines, opts.start_line, opts.end_line) }
  for _, line in ipairs(selected_lines) do
    local match = string.match(line, "^%s*(`+)%s*$")
    if match and #match >= #backticks then
      backticks = match .. "`"
    end
  end
  local suggestion_lines = { backticks .. "suggestion:-" .. (opts.end_line - opts.start_line) .. "+0" }
  vim.list_extend(suggestion_lines, selected_lines)
  table.insert(suggestion_lines, backticks)
  return suggestion_lines
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
---@param end_line integer The last line number of the comment range.
---@param original_lines string[] Array of original lines.
---@return Suggestion[] suggestions List of suggestion data.
local get_suggestions = function(note_lines, end_line, original_lines)
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
      local start_line = end_line - suggestion.start_line_offset
      local end_line_number = end_line + suggestion.end_line_offset
      suggestion.full_text =
        replace_line_range(original_lines, start_line, end_line_number, suggestion.lines, suggestion.note_start_linenr)

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
      },
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

---Decide if local file should be used to show suggestion preview.
---@param opts ShowPreviewOpts The options passed to the M.show_preview function.
local determine_imply_local = function(opts)
  local head_differs_from_original = git.file_differs_in_revisions({
    revision_1 = opts.revision,
    revision_2 = "HEAD",
    old_file_name = opts.old_file_name,
    file_name = opts.new_file_name,
  })
  -- TODO: Find out if this condition is not too restrictive (comment on unchanged lines could be
  -- shown in local file just fine). Ideally, change logic of showing comments on unchanged lines
  -- from OLD to NEW version (to enable more local-file diffing).
  if not opts.is_new_sha then
    u.notify("Comment on old text. Using target-branch version", vim.log.levels.WARN)
  elseif head_differs_from_original then
    u.notify("Line changed. Using version for which comment was made", vim.log.levels.WARN)
  elseif is_modified(opts.new_file_name) then
    u.notify("File has unsaved or uncommited changes", vim.log.levels.WARN)
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

---Get the highlighted text for the edit mode of the suggestion buffer.
---@param imply_local boolean True if suggestion buffer is local file and should be written.
---@return string
local get_edit_mode = function(imply_local)
  if imply_local then
    return "%#GitlabLiveMode#Local file"
  else
    return "%#GitlabDraftMode#Temp file"
  end
end

---Get the highlighted text for the draft mode.
---@param opts ShowPreviewOpts The options passed to the M.show_preview function.
---@return string
local get_draft_mode = function(opts)
  if opts.comment_type == "draft" or opts.comment_type == "edit" then
    return ""
  end
  if require("gitlab.state").settings.discussion_tree.draft_mode then
    return "%#GitlabDraftMode#Draft"
  else
    return "%#GitlabLiveMode#Live"
  end
end

---Update the winbar on top of the suggestion preview windows.
---@param note_winid integer Note window number.
---@param suggestion_winid integer Suggestion window number in the preview tab.
---@param original_winid integer Original text window number in the preview tab.
---@param imply_local boolean True if suggestion buffer is local file and should be written.
---@param opts ShowPreviewOpts The options passed to the M.show_preview function.
local update_winbar = function(note_winid, suggestion_winid, original_winid, imply_local, opts)
  if original_winid ~= -1 then
    local content = string.format(" %s: %s ", "%#Normal#original", "%#GitlabUserName#" .. opts.revision)
    vim.api.nvim_set_option_value("winbar", content, { scope = "local", win = original_winid })
  end

  if suggestion_winid ~= -1 then
    local content = string.format(" %s: %s ", "%#Normal#mode", get_edit_mode(imply_local))
    vim.api.nvim_set_option_value("winbar", content, { scope = "local", win = suggestion_winid })
  end

  if note_winid ~= -1 then
    local content = string.format(
      " %s: %s %s ",
      "%#Normal#" .. opts.comment_type,
      "%#GitlabUserName#" .. opts.note_header,
      get_draft_mode(opts)
    )
    vim.api.nvim_set_option_value("winbar", content, { scope = "local", win = note_winid })
  end
end

---Create autocommands for the note buffer.
---@param note_buf integer Note buffer number.
---@param note_winid integer Note window number.
---@param suggestion_buf integer Suggestion buffer number.
---@param suggestion_winid integer Suggestion window number in the preview tab.
---@param original_winid integer Original text window number in the preview tab.
---@param suggestions Suggestion[] List of suggestion data.
---@param original_lines string[] Array of original lines.
---@param imply_local boolean True if suggestion buffer is local file and should be written.
---@param opts ShowPreviewOpts The options passed to the M.show_preview function.
local create_autocommands = function(
  note_buf,
  note_winid,
  suggestion_buf,
  suggestion_winid,
  original_winid,
  suggestions,
  original_lines,
  imply_local,
  opts
)
  local last_line, last_suggestion = suggestions[1].note_start_linenr, suggestions[1]

  ---Update the suggestion buffer if the selected suggestion changes in the Comment buffer.
  local update_suggestion_buffer = function()
    local current_line = vim.fn.line(".")
    if current_line == last_line then
      return
    end
    local suggestion = List.new(suggestions):find(function(sug)
      return current_line <= sug.note_end_linenr
    end)
    if not suggestion or suggestion == last_suggestion then
      return
    end
    set_buffer_lines(suggestion_buf, suggestion.full_text, imply_local)
    last_line, last_suggestion = current_line, suggestion
    refresh_signs(suggestion, note_buf)
  end

  -- Create autocommand to update the Suggestion buffer when the cursor moves in the Comment buffer.
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    buffer = note_buf,
    callback = function()
      update_suggestion_buffer()
    end,
  })

  -- Create autocommand to update suggestions list based on the note buffer content.
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    buffer = note_buf,
    callback = function()
      local updated_note_lines = vim.api.nvim_buf_get_lines(note_buf, 0, -1, false)
      suggestions = get_suggestions(updated_note_lines, opts.end_line, original_lines)
      last_line = 0
      update_suggestion_buffer()
      refresh_diagnostics(suggestions, note_buf)
    end,
  })

  -- Update the note buffer header when draft mode is toggled.
  local group = vim.api.nvim_create_augroup("GitlabDraftModeToggled" .. note_buf, { clear = true })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "GitlabDraftModeToggled",
    callback = function()
      update_winbar(note_winid, suggestion_winid, original_winid, imply_local, opts)
    end,
  })
  -- Auto-delete the group when the buffer is unloaded.
  vim.api.nvim_create_autocmd("BufUnload", {
    buffer = note_buf,
    group = group,
    callback = function()
      vim.api.nvim_del_augroup_by_id(group)
    end,
  })
end

---@class ShowPreviewOpts The options passed to the M.show_preview function.
---@field old_file_name string
---@field new_file_name string
---@field start_line integer
---@field end_line integer
---@field is_new_sha boolean
---@field revision string
---@field note_header string
---@field comment_type "apply"|"reply"|"draft"|"edit"|"new" The type of comment ("apply", "reply", "draft" and "edit" come from the discussion tree, "new" from the reviewer)
---@field note_lines string[]|nil
---@field root_node_id string
---@field note_node_id integer

---Get suggestions from the current note and preview them in a new tab.
---@param opts ShowPreviewOpts The options passed to the M.show_preview function.
M.show_preview = function(opts)
  if not git.revision_exists(opts.revision) then
    u.notify(
      string.format("Revision `%s` for which the comment was made does not exist", opts.revision),
      vim.log.levels.ERROR
    )
    return
  end

  local commented_file_name = opts.is_new_sha and opts.new_file_name or opts.old_file_name
  local original_buf_name, original_bufnr =
    get_temp_file_name("ORIGINAL", opts.note_node_id or "NEW_COMMENT", commented_file_name)

  -- If preview is already open for given note, go to the tab with a warning.
  local tabnr = get_tabnr_for_buf(original_bufnr)
  if tabnr ~= nil then
    vim.api.nvim_set_current_tabpage(tabnr)
    u.notify("Previously created preview can be outdated", vim.log.levels.WARN)
    return
  end

  local original_lines = get_original_lines(opts)
  if original_lines == nil then
    return
  end

  local note_lines = opts.note_lines or get_default_suggestion(original_lines, opts)
  local suggestions = get_suggestions(note_lines, opts.end_line, original_lines)

  -- Create new tab with a temp buffer showing the original version on which the comment was
  -- made.
  vim.fn.mkdir(vim.fn.fnamemodify(original_buf_name, ":h"), "p")
  vim.api.nvim_cmd({ cmd = "tabnew", args = { original_buf_name } }, {})
  local original_buf = vim.api.nvim_get_current_buf()
  local original_winid = vim.api.nvim_get_current_win()
  vim.api.nvim_buf_set_lines(original_buf, 0, -1, false, original_lines)
  vim.bo.bufhidden = "wipe"
  vim.bo.buflisted = false
  vim.bo.buftype = "nofile"
  vim.bo.modifiable = false
  vim.cmd.filetype("detect")
  local buf_filetype = vim.api.nvim_get_option_value("filetype", { buf = 0 })

  local imply_local = determine_imply_local(opts)

  -- Create the suggestion buffer and show a diff with the original version
  local split_cmd = vim.o.columns > 240 and "vsplit" or "split"
  if imply_local then
    vim.api.nvim_cmd({ cmd = split_cmd, args = { opts.new_file_name } }, {})
  else
    local sug_buf_name = get_temp_file_name("SUGGESTION", opts.note_node_id or "NEW_COMMENT", commented_file_name)
    vim.fn.mkdir(vim.fn.fnamemodify(sug_buf_name, ":h"), "p")
    vim.api.nvim_cmd({ cmd = split_cmd, args = { sug_buf_name } }, {})
    vim.bo.bufhidden = "wipe"
    vim.bo.buflisted = false
    vim.bo.buftype = "nofile"
    vim.bo.filetype = buf_filetype
  end
  local suggestion_buf = vim.api.nvim_get_current_buf()
  local suggestion_winid = vim.api.nvim_get_current_win()
  set_buffer_lines(suggestion_buf, suggestions[1].full_text, imply_local)
  vim.cmd("1,2windo diffthis")

  -- Backup the suggestion buffer winbar to reset it when suggestion preview is closed. Despite the
  -- option being "window-local", it's carried over to the buffer even after closing the preview.
  -- See https://github.com/neovim/neovim/issues/11525
  local suggestion_winbar = vim.api.nvim_get_option_value("winbar", { scope = "local", win = suggestion_winid })

  -- Create the note window
  local note_buf = vim.api.nvim_create_buf(false, false)
  local note_winid = vim.fn.win_getid(3)
  local note_bufname = vim.fn.tempname()
  vim.api.nvim_buf_set_name(note_buf, note_bufname)
  vim.api.nvim_cmd({ cmd = "vnew", mods = { split = "botright" }, args = { note_bufname } }, {})
  vim.api.nvim_buf_set_lines(note_buf, 0, -1, false, note_lines)
  vim.bo.bufhidden = "wipe"
  vim.bo.buflisted = false
  vim.bo.filetype = "markdown"
  vim.bo.modified = false

  -- Set up keymaps and autocommands
  local default_suggestion_lines = get_default_suggestion(original_lines, opts)
  set_keymaps(
    note_buf,
    original_buf,
    suggestion_buf,
    original_lines,
    imply_local,
    default_suggestion_lines,
    suggestion_winbar,
    suggestion_winid,
    opts
  )
  create_autocommands(
    note_buf,
    note_winid,
    suggestion_buf,
    suggestion_winid,
    original_winid,
    suggestions,
    original_lines,
    imply_local,
    opts
  )

  -- Focus the note window on the first suggestion
  vim.api.nvim_win_set_cursor(note_winid, { suggestions[1].note_start_linenr, 0 })
  refresh_signs(suggestions[1], note_buf)
  refresh_diagnostics(suggestions, note_buf)
  update_winbar(note_winid, suggestion_winid, original_winid, imply_local, opts)
end

return M
