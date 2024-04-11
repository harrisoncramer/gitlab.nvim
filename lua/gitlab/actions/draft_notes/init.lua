local au = require("gitlab.actions.utils")
local NuiTree = require("nui.tree")
local List = require("gitlab.utils.list")
local u = require("gitlab.utils")
local state = require("gitlab.state")
local help = require("gitlab.actions.help")
local winbar = require("gitlab.actions.discussions.winbar")

local M = {
  bufnr = nil,
  ---@type DraftNote[]
  draft_notes = nil,
  tree = nil,
}

--- Adds a draft note to the draft notes state, then rebuilds the view
--- @param draft_note DraftNote
M.add_draft_note = function(draft_note)
  local new_draft_notes = state.DRAFT_NOTES
  table.insert(new_draft_notes, draft_note)
  state.DRAFT_NOTES = new_draft_notes
end

--- @param bufnr integer
M.set_bufnr = function(bufnr)
  M.bufnr = bufnr
end

M.rebuild_draft_notes_view = function()
  u.switch_can_edit_buf(M.bufnr, true)
  vim.api.nvim_set_option_value("filetype", "gitlab", { buf = M.draft_notes_bufnr })
  local draft_notes = List.new(state.DRAFT_NOTES)

  au.add_empty_titles({
    { bufnr = M.bufnr, data = state.DRAFT_NOTES, title = "No Draft Notes for this MR" },
  })

  local draft_note_nodes = draft_notes:map(function(note)
    local _, root_text, root_text_nodes = au.build_note(note)
    return NuiTree.Node({
      range = (type(note.position) == "table" and note.position.line_range or nil),
      text = root_text,
      type = "note",
      is_root = true,
      id = note.id,
      root_note_id = note.id,
      file_name = (type(note.position) == "table" and note.position.new_path or nil),
      new_line = (type(note.position) == "table" and note.position.new_line or nil),
      old_line = (type(note.position) == "table" and note.position.old_line or nil),
      resolvable = false,
      resolved = false,
      url = state.INFO.web_url .. "#note_" .. note.id,
    }, root_text_nodes)
  end)

  local tree = NuiTree({ nodes = draft_note_nodes, bufnr = M.bufnr, prepare_node = au.nui_tree_prepare_node })
  M.tree = tree

  tree:render()
  M.set_keymaps()
end

M.refresh_view = function()
  -- diagnostics.refresh_diagnostics(state.DRAFT_NOTES)
  winbar.update_winbar()
  local discussions = require("gitlab.actions.discussions")
  if discussions.split_visible then
    winbar.update_winbar()
  end
end

M.set_keymaps = function()
  vim.keymap.set("n", state.settings.discussion_tree.edit_comment, function()
    M.edit_comment()
  end, { buffer = M.bufnr, desc = "Edit comment" })
  vim.keymap.set("n", state.settings.discussion_tree.delete_comment, function()
    M.delete_comment()
  end, { buffer = M.bufnr, desc = "Delete comment" })
  vim.keymap.set("n", state.settings.discussion_tree.switch_view, function()
    winbar.switch_view_type()
  end, { buffer = M.bufnr, desc = "Switch view type" })
  vim.keymap.set("n", state.settings.help, function()
    help.open()
  end, { buffer = M.bufnr, desc = "Open help popup" })
  vim.keymap.set("n", state.settings.discussion_tree.toggle_node, function()
    au.toggle_node(M.tree)
  end, { buffer = M.bufnr, desc = "Toggle node" })
  vim.keymap.set("n", state.settings.discussion_tree.jump_to_file, function()
    au.jump_to_file(M.tree)
  end, { buffer = M.bufnr, desc = "Jump to file" })
  vim.keymap.set("n", state.settings.discussion_tree.jump_to_reviewer, function()
    au.jump_to_reviewer(M.tree, M.refresh_view)
  end, { buffer = M.bufnr, desc = "Jump to reviewer" })
  vim.keymap.set("n", state.settings.discussion_tree.open_in_browser, function()
    au.open_in_browser(M.tree) -- For some reason, I cannot see my own draft notes in Gitlab's UI
  end, { buffer = M.bufnr, desc = "Open the note in your browser" })
  vim.keymap.set("n", state.settings.discussion_tree.copy_node_url, function()
    au.copy_node_url(M.tree)
  end, { buffer = M.bufnr, desc = "Copy the URL of the current node to clipboard" })
  vim.keymap.set("n", "<leader>p", function()
    au.print_node()
  end, { buffer = M.bufnr, desc = "Print current node (for debugging)" })
  vim.keymap.set("n", state.settings.discussion_tree.toggle_all_discussions, function()
    local discussions = require("gitlab.actions.discussions")
    au.toggle_nodes(discussions.split.winid, M.tree, false, {
      toggle_resolved = true,
      toggle_unresolved = true,
      keep_current_open = state.settings.discussion_tree.keep_current_open,
    })
  end, { buffer = M.bufnr, desc = "Toggle all nodes" })
end

M.edit_comment = function()
  u.notify("Not implemented yet")
end

M.delete_comment = function()
  u.notify("Not implemented yet")
end

return M
