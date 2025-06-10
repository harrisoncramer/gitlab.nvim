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
local note_header_namespace = vim.api.nvim_create_namespace("gitlab_suggestion_note_header")

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
---@param root_node NuiTreeNode|nil The first comment in the discussion thread (can be a draft comment), nil if a new comment is created.
---@param note_node NuiTreeNode|nil The first node of a comment or reply, nil if a new comment is created.
---@param imply_local boolean True if suggestion buffer is local file and should be written.
---@param default_suggestion_lines string[] The default suggestion lines with backticks.
---@param is_reply boolean|nil True if the suggestion comment is a reply to a thread.
---@param is_new_comment boolean True if the suggestion is a new comment.
local set_keymaps = function(note_buf, original_buf, suggestion_buf, original_lines, root_node, note_node, imply_local, default_suggestion_lines, is_reply, is_new_comment)
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

      if note_node and root_node then
        local note_id = tonumber(note_node.is_root and note_node.root_note_id or note_node.id)
        local edit_action = note_node.is_draft
          and require("gitlab.actions.draft_notes").confirm_edit_draft_note(note_id, false)
            or require("gitlab.actions.comment").confirm_edit_comment(root_node.id, note_id, false)
        edit_action(u.get_buffer_text(note_buf))
      elseif root_node and is_reply then
        require("gitlab.actions.comment").confirm_create_comment(u.get_buffer_text(note_buf), false, root_node.id)
      elseif is_new_comment then
        require("gitlab.actions.comment").confirm_create_comment(u.get_buffer_text(note_buf), false)
      else
        -- This should not really happen.
        u.notify("Cannot create comment", vim.log.levels.ERROR)
      end

      set_buffer_lines(suggestion_buf, original_lines, imply_local)
      vim.cmd.tabclose()
    end, { buffer = note_buf, desc = "Post suggestion comment to Gitlab", nowait = keymaps.suggestion_preview.apply_changes_nowait  })
  end

  if keymaps.suggestion_preview.paste_default_suggestion then
    vim.keymap.set("n", keymaps.suggestion_preview.paste_default_suggestion, function()
      vim.api.nvim_put(default_suggestion_lines, "l", true, false)
    end, { buffer = note_buf, desc = "Paste default suggestion", nowait = keymaps.suggestion_preview.paste_default_suggestion_nowait  })
  end

  -- TODO: Keymap for applying changes to the Suggestion buffer.
  -- TODO: Keymap for showing help on keymaps in the Comment buffer and Suggestion buffer.
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

---Create the default suggestion lines for given comment range.
---@param original_lines string[] The list of lines in the original (commented on) version of the file.
---@param start_line_number integer The start line of the range of the comment (1-based indexing).
---@param end_line_number integer The end line of the range of the comment.
---@return string[] suggestion_lines
local get_default_suggestion = function(original_lines, start_line_number, end_line_number)
  local backticks = "```"
  local selected_lines = {unpack(original_lines, start_line_number, end_line_number)}
  for _, line in ipairs(selected_lines) do
    local match = string.match(line, "^%s*(`+)%s*$")
    if match and #match >= #backticks then
      backticks = match .. "`"
    end
  end
  local suggestion_lines = {backticks .. "suggestion:-" .. (end_line_number - start_line_number) .. "+0"}
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

---Decide if local file should be used to show suggestion preview.
---@param revision string The revision of the file for which the comment was made.
---@param is_new_sha boolean True if line number refers to NEW SHA
---@param original_file_name string The name of the file on which the comment was made.
---@param new_file_name string The new name of the file on which the comment was made.
local determine_imply_local = function(revision, is_new_sha, original_file_name, new_file_name)
  local head_differs_from_original = git.file_differs_in_revisions({
    original_revision = revision,
    head_revision = "HEAD",
    old_file_name = original_file_name,
    file_name = new_file_name,
  })
  -- TODO: Find out if this condition is not too restrictive.
  if not is_new_sha then
    u.notify(
      string.format("Comment on unchanged text. Using target-branch version of `%s`", original_file_name),
      vim.log.levels.INFO
    )
  -- TODO: Find out if this condition is not too restrictive (maybe instead check if a later comment in the thread matches "^changed this line in [version %d+ of the diff]").
  -- TODO: Rework to be able to switch between diffing against current head and original head.
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

---Get the text for the draft mode
---@param is_reply boolean|nil True if the suggestion comment is a reply to a thread.
---@param is_new_comment boolean True if the suggestion is a new comment.
---@return string[]|nil
local get_mode = function(is_reply, is_new_comment)
  if not is_reply and not is_new_comment then
    return
  end
  if require("gitlab.state").settings.discussion_tree.draft_mode then
    return { " Draft", "GitlabDraftMode" }
  else
    return { " Live", "GitlabLiveMode" }
  end
end

---Show the note header as virtual text.
---@param text string The text to show in the header.
---@param note_buf integer The number of the note buffer.
---@param is_reply boolean|nil True if the suggestion comment is a reply to a thread.
---@param is_new_comment boolean True if the suggestion is a new comment.
local add_window_header = function(text, note_buf, is_reply, is_new_comment)
  vim.api.nvim_buf_clear_namespace(note_buf, note_header_namespace, 0, -1)
  local mark_opts = {
    virt_lines = { { { is_reply and "Reply to: " or is_new_comment and "Create: " or "Edit: ", "Normal" }, { text, "GitlabUserName" }, get_mode(is_reply, is_new_comment) } },
    virt_lines_above = true,
    right_gravity = false,
  }
  vim.api.nvim_buf_set_extmark(note_buf, note_header_namespace, 0, 0, mark_opts)
  -- An extmark above the first line is not visible by default, so let's scroll the window:
  vim.cmd("normal! ")
  -- TODO: Replace with winbar, possibly also show the diffed revision of the ORIGINAL.
  -- Extmarks are not ideal for this because of scrolling issues.
end

---Create autocommands for the note buffer.
---@param note_buf integer Note buffer number.
---@param suggestion_buf integer Suggestion buffer number.
---@param suggestions Suggestion[] List of suggestion data.
---@param end_line_number integer The last number of the comment range.
---@param original_lines string[] Array of original lines.
---@param imply_local boolean True if suggestion buffer is local file and should be written.
---@param is_reply boolean|nil True if the suggestion comment is a reply to a thread.
---@param is_new_comment boolean True if the suggestion is a new comment.
local create_autocommands = function(note_buf, suggestion_buf, suggestions, end_line_number, original_lines, imply_local, note_header, is_reply, is_new_comment)
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
  vim.api.nvim_create_autocmd({"CursorMoved", "CursorMovedI"}, {
    buffer = note_buf,
    callback = function()
      update_suggestion_buffer()
    end,
  })

  -- Create autocommand to update suggestions list based on the note buffer content.
  vim.api.nvim_create_autocmd({"TextChanged", "TextChangedI"}, {
    buffer = note_buf,
    callback = function()
      local updated_note_lines = vim.api.nvim_buf_get_lines(note_buf, 0, -1, false)
      suggestions = get_suggestions(updated_note_lines, end_line_number, original_lines)
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
      add_window_header(note_header, note_buf, is_reply, is_new_comment)
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

---TODO: Enable "reply_with_suggestion" from discussion tree.
---TODO: Enable "create_comment_with_suggestion" from reviewe.r
---Get suggestions from the current note and preview them in a new tab.
---@param tree NuiTree|nil The current discussion tree instance.
---@param is_reply boolean|nil True if the suggestion comment is a reply to a thread.
---@param location Location|nil The location of the visual selection in the reviewer.
M.show_preview = function(tree, is_reply, location)

  local start_line_number, end_line_number, is_new_sha, revision
  local root_node, note_node
  local note_buf_header_text, comment_id
  local original_file_name, new_file_name
  local is_new_comment = false
  -- Populate necessary variables from the discussion tree
  if tree ~= nil then
    local current_node = tree:get_node()
    root_node = common.get_root_node(tree, current_node)
    note_node = common.get_note_node(tree, current_node)
    note_buf_header_text = note_node.text
    comment_id = note_node.id
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
    start_line_number, is_new_sha, end_line_number = common.get_line_number_from_node(root_node)
    if is_new_sha then
      revision = root_node.head_sha
      original_file_name = root_node.file_name
    else
      revision = root_node.base_sha
      original_file_name = root_node.old_file_name
    end
    new_file_name = root_node.file_name

  -- Populate necessary variables from the reviewer location data
  elseif location ~= nil then
    note_buf_header_text = "New comment"
    comment_id = "HEAD"
    start_line_number = location.visual_range.start_line
    end_line_number = location.visual_range.end_line
    is_new_sha = location.reviewer_data.new_sha_focused
    revision = is_new_sha and "HEAD" or require("gitlab.state").INFO.target_branch
    original_file_name = location.reviewer_data.file_name or location.reviewer_data.old_file_name
    new_file_name = location.reviewer_data.file_name
    is_new_comment = true
  else
    u.notify("Cannot create comment", vim.log.levels.ERROR)
    return
  end

  if not git.revision_exists(revision) then
    u.notify(
      string.format("Revision `%s` for which the comment was made does not exist", revision),
      vim.log.levels.WARN
    )
    return
  end

  -- If preview is already open for given note, go to the tab with a warning.
  local original_buf_name, original_bufnr = get_temp_file_name("ORIGINAL", comment_id, original_file_name)
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

  local note_lines
  if tree and not is_reply then
    note_lines = common.get_note_lines(tree)
  else
    note_lines = get_default_suggestion(original_lines, start_line_number, end_line_number)
  end
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

  local imply_local = determine_imply_local(revision, is_new_sha, original_file_name, new_file_name)

  -- Create the suggestion buffer and show a diff with the original version
  local split_cmd = vim.o.columns > 240 and "vsplit" or "split"
  if imply_local then
    vim.api.nvim_cmd({ cmd = split_cmd, args = { original_file_name } }, {})
  else
    local sug_buf_name = get_temp_file_name("SUGGESTION", comment_id, new_file_name)
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
  local default_suggestion_lines = get_default_suggestion(original_lines, start_line_number, end_line_number)
  set_keymaps(note_buf, original_buf, suggestion_buf, original_lines, root_node, note_node, imply_local, default_suggestion_lines, is_reply, is_new_comment)
  create_autocommands(note_buf, suggestion_buf, suggestions, end_line_number, original_lines, imply_local, note_buf_header_text, is_reply, is_new_comment)

  -- Focus the note window on the first suggestion
  local note_winid = vim.fn.win_getid(3)
  vim.api.nvim_win_set_cursor(note_winid, { suggestions[1].note_start_linenr, 0 })
  refresh_signs(suggestions[1], note_buf)
  refresh_diagnostics(suggestions, note_buf)
  add_window_header(note_buf_header_text, note_buf, is_reply, is_new_comment)
end

return M
