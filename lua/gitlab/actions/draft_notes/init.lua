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
    { bufnr = M.bufnr, data = state.DRAFT_NOTES, title = "No Draft Notes for this MR" }
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
  M.set_keymaps(true)
end

M.set_keymaps = function(unlinked)
  -- vim.keymap.set("n", state.settings.discussion_tree.edit_comment, function()
  --   M.edit_comment()
  -- end, { buffer = M.bufnr, desc = "Edit comment" })
  -- vim.keymap.set("n", state.settings.discussion_tree.delete_comment, function()
  --   M.delete_comment()
  -- end, { buffer = M.bufnr, desc = "Delete comment" })
  vim.keymap.set("n", state.settings.discussion_tree.switch_view, function()
    winbar.switch_view_type()
  end, { buffer = M.bufnr, desc = "Switch view type" })
  vim.keymap.set("n", state.settings.help, function()
    help.open()
  end, { buffer = M.bufnr, desc = "Open help popup" })
  vim.keymap.set("n", state.settings.discussion_tree.toggle_node, function()
    au.toggle_node(M.tree)
  end, { buffer = bufnr, desc = "Toggle node" })
  -- if not unlinked then
  --   vim.keymap.set("n", state.settings.discussion_tree.jump_to_file, function()
  --     M.jump_to_file()
  --   end, { buffer = M.bufnr, desc = "Jump to file" })
  --   vim.keymap.set("n", state.settings.discussion_tree.jump_to_reviewer, function()
  --     M.jump_to_reviewer()
  --   end, { buffer = M.bufnr, desc = "Jump to reviewer" })
  -- end
  -- vim.keymap.set("n", state.settings.discussion_tree.open_in_browser, function()
  --   M.open_in_browser()
  -- end, { buffer = M.bufnr, desc = "Open the note in your browser" })
  -- vim.keymap.set("n", state.settings.discussion_tree.copy_node_url, function()
  --   M.copy_node_url()
  -- end, { buffer = M.bufnr, desc = "Copy the URL of the current node to clipboard" })
  -- vim.keymap.set("n", "<leader>p", function()
  --   M.print_node()
  -- end, { buffer = M.bufnr, desc = "Print current node (for debugging)" })
end

return M
