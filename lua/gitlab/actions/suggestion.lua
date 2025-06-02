--- This module is responsible for previewing changes suggested in comments.
--- The data required to make the API calls are drawn from the discussion nodes.

local common = require("gitlab.actions.common")
local diffview_lib = require("diffview.lib")
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

local set_buffer_lines = function(bufnr, lines)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  if M.local_implied then
    vim.api.nvim_buf_call(bufnr, function()
      vim.api.nvim_cmd({ cmd = "write", mods = { silent = true } }, {})
    end)
  end
end

local set_keymaps = function(note_buf, original_buf, suggestion_buf, original_lines)
  for _, bufnr in ipairs({ note_buf, original_buf, suggestion_buf }) do
    vim.keymap.set("n", "q", function()
      vim.cmd.tabclose()
      if original_buf ~= nil then
        if vim.api.nvim_buf_is_valid(original_buf) then
          vim.cmd.bwipeout(original_buf)
        end
      end
      if suggestion_buf ~= nil then
        if vim.api.nvim_buf_is_valid(suggestion_buf) then
          vim.api.nvim_set_option_value("modifiable", true, { buf = suggestion_buf })
          set_buffer_lines(suggestion_buf, original_lines)
        end
      end
      -- TODO: restore suggestion buffer if it's HEAD!
    end, { buffer = bufnr, desc = "Close suggestion preview tab" })
  end
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
    for _, winnr in ipairs( vim.api.nvim_tabpage_list_wins(tabnr)) do
      if vim.api.nvim_win_get_buf(winnr) == bufnr then
        return tabnr
      end
    end
  end
  return nil
end

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

local create_diagnostics = function(suggestions)
  local diagnostics_data = {}
  for _, suggestion in ipairs(suggestions) do
    local diagnostic = {
      message = table.concat(suggestion.lines, "\n") .. "\n",
      col = 0,
      severity = vim.diagnostic.severity.INFO,
      source = "gitlab",
      code = "gitlab.nvim",
      lnum = suggestion.note_start_linenr - 1
    }
    table.insert(diagnostics_data, diagnostic)
  end
  return diagnostics_data
end

---@class ShowPreviewOpts
---@field tree NuiTree The current discussion tree instance
---@field node NuiTreeNode The current node in the discussion tree

---Get suggestions from the current note and preview them in a new tab
---@param opts ShowPreviewOpts
M.show_preview = function(opts)
  local root_node = common.get_root_node(opts.tree, opts.node)
  if root_node == nil then
    u.notify("Couldn't get root node", vim.log.levels.ERROR)
    return
  end

  -- If preview is already open for given note, go to the tab with a warning.
  local note_bufname = string.format("gitlab://NOTE/%s", root_node._id)
  local tabnr = get_tabnr_for_buf(note_bufname)
  if tabnr ~= nil then
    vim.api.nvim_set_current_tabpage(tabnr)
    u.notify("Previously created preview can be outdated", vim.log.levels.WARN)
    return
  end

  -- Return early when there're no suggestions.
  local note_lines = common.get_note_lines(opts.tree)
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
    u.notify(string.format("Revision `%s` for which the comment was made does not exist", revision),
      vim.log.levels.WARN)
    return
  end

  local original_head_text = git.get_file_revision({ file_name = original_file_name, revision = revision })
  local head_text = git.get_file_revision({ file_name = root_node.file_name, revision = "HEAD" })

  -- The original head_sha doesn't contain the file, the branch was possibly rebased, and the
  -- original head_sha could not been found. In that case `git.get_file_revision` should have logged
  -- an error.
  if original_head_text == nil then
    u.notify(
      string.format("File `%s` doesn't contain any text in revision `%s` for which the comment was made", original_file_name, revision),
      vim.log.levels.WARN
    )
    return
  end

  local view = diffview_lib.get_current_view()
  if view == nil then
    u.notify("Could not find Diffview view", vim.log.levels.ERROR)
    return
  end

  -- TODO: Use some common function to get the current file, deal with possible renames, decide if
  -- the suggestion was made for the OLD version or NEW, etc.
  local files = view.panel:ordered_file_list()
  local file_name = List.new(files):find(function(file)
    local file_name_ = is_new_sha and file.path or file.oldpath
    return file_name_ ==  original_file_name
  end)

  if file_name == nil then
    u.notify(string.format("File `%s` not found in revision `%s`.", revision))
    return
  end

  -- Create new tab with a temp buffer showing the original version on which the comment was
  -- made.
  local original_lines = vim.fn.split(original_head_text, "\n", true)
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
  local buf_filetype = vim.api.nvim_get_option_value('filetype', { buf = 0 })

  -- TODO: Don't use local version when file contains changes (reuse `lua/gitlab/actions/comment.lua` lines 336-350)
  if original_head_text == head_text and is_new_sha then
    -- TODO: add check that file is not modified or doesn't have local uncommitted changes
    u.notify("Original head is the same as HEAD. Using local version of " .. original_file_name,
      vim.log.levels.INFO
    )
    vim.api.nvim_cmd({ cmd = "vsplit", args = { file_name.path } }, {})
    M.local_implied = true
  else
    -- TODO: Handle renamed files
    if is_new_sha then
      u.notify(
        "Original head differs from HEAD. Using original version of " .. file_name.path,
        vim.log.levels.WARNING
      )
    else
      u.notify(
        "Comment was made on unchanged text. Using original version of " .. file_name.path,
        vim.log.levels.WARNING
      )
    end
    local sug_file_name = get_temp_file_name("SUGGESTION", root_node._id, root_node.file_name)
    vim.fn.mkdir(vim.fn.fnamemodify(sug_file_name, ":h"), "p")
    vim.api.nvim_cmd({ cmd = "vnew", args = { sug_file_name } }, {})
    vim.bo.bufhidden = "wipe"
    vim.bo.buflisted = false
    vim.bo.buftype = "nofile"
    vim.bo.filetype = buf_filetype
    M.local_implied = false
  end

  local suggestion_buf = vim.api.nvim_get_current_buf()

  -- Create the file texts with suggestions applied
  for _, suggestion in ipairs(suggestions) do
    -- subtract 1 because nvim_buf_set_lines indexing is zero-based
    local start_line = end_line_number - suggestion.start_line_offset
    -- don't subtract 1 because nvim_buf_set_lines indexing is end-exclusive
    local end_line = end_line_number + suggestion.end_line_offset

    suggestion.full_text = replace_range(original_lines, start_line, end_line, suggestion.lines)
  end
  set_buffer_lines(suggestion_buf, suggestions[1].full_text)

  vim.cmd("1,2windo diffthis")

  -- Create the note window
  local note_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(note_buf, note_bufname)
  vim.api.nvim_cmd({ cmd = "vnew", args = { note_bufname } }, {})
  vim.api.nvim_buf_set_lines(note_buf, 0, -1, false, note_lines)
  vim.bo.bufhidden = "wipe"
  vim.bo.buflisted = false
  vim.bo.buftype = "nofile"
  vim.bo.filetype = "markdown"
  vim.bo.modifiable = false

  -- Focus the note window
  local note_winid = vim.fn.win_getid(3)
  vim.api.nvim_win_set_cursor(note_winid, { suggestions[1].note_start_linenr, 0 })
  refresh_signs(suggestions[1], note_buf)
  set_keymaps(note_buf, original_buf, suggestion_buf, original_lines)

  -- Create autocommand for showing the active suggestion buffer in window 2
  local last_line = suggestions[1].note_start_linenr
  local last_suggestion = suggestions[1]
  vim.api.nvim_create_autocmd({ "CursorMoved" }, {
    buffer = note_buf,
    callback = function()
      local current_line = vim.fn.line('.')
      if current_line ~= last_line then
        local suggestion = List.new(suggestions):find(function(sug)
          return current_line <= sug.note_end_linenr
        end)
        if suggestion ~= last_suggestion then
          set_buffer_lines(suggestion_buf, suggestion.full_text)
          last_line = current_line
          last_suggestion = suggestion
          refresh_signs(suggestion, note_buf)
        end
      end
    end
  })

  -- Show diagnostics for suggestions (enables using built-in navigation)
  local diagnostics_data = create_diagnostics(suggestions)
  vim.diagnostic.set(suggestion_namespace, note_buf, diagnostics_data, indicators_common.create_display_opts())

  -- Show the discussion heading as virtual text
  local mark_opts = { virt_lines = { { { opts.node.text, "WarningMsg" } } }, virt_lines_above = true }
  vim.api.nvim_buf_set_extmark(note_buf, suggestion_namespace, 0, 0, mark_opts)
  -- An extmark above the first line is not visible by default, so let's scroll the window:
  vim.cmd("normal! ")
  -- TODO: Add virtual text (or winbar?) to show the diffed revision of the ORIGINAL.
end

return M
