local common = require("gitlab.actions.common")
local trees = require("gitlab.actions.trees")
local job = require("gitlab.job")
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
  M.rebuild_draft_notes_tree()
end

--- @param bufnr integer
M.set_bufnr = function(bufnr)
  M.bufnr = bufnr
end

M.rebuild_draft_notes_tree = function()
  if M.bufnr == nil then
    return
  end

  u.switch_can_edit_buf(M.bufnr, true)
  vim.api.nvim_buf_set_lines(M.bufnr, 0, -1, false, {})
  vim.api.nvim_set_option_value("filetype", "gitlab", { buf = M.draft_notes_bufnr })

  local draft_notes = List.new(state.DRAFT_NOTES)

  common.add_empty_titles({
    { bufnr = M.bufnr, data = state.DRAFT_NOTES, title = "No Draft Notes for this MR" },
  })

  local draft_note_nodes = draft_notes:map(function(note)
    local _, root_text, root_text_nodes = trees.build_note(note)
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

  local tree = NuiTree({ nodes = draft_note_nodes, bufnr = M.bufnr, prepare_node = trees.nui_tree_prepare_node })
  M.tree = tree

  tree:render()
  winbar.update_winbar()
  M.set_keymaps()
end

M.refresh_view = function()
  -- TODO: Implement diagnostics
end

M.set_keymaps = function()
  vim.keymap.set("n", state.settings.discussion_tree.edit_comment, function()
    M.edit_draft_note()
  end, { buffer = M.bufnr, desc = "Edit comment" })
  vim.keymap.set("n", state.settings.discussion_tree.delete_comment, function()
    M.delete_draft_note(M.tree)
  end, { buffer = M.bufnr, desc = "Delete comment" })
  vim.keymap.set("n", state.settings.discussion_tree.switch_view, function()
    winbar.switch_view_type()
  end, { buffer = M.bufnr, desc = "Switch view type" })
  vim.keymap.set("n", state.settings.help, function()
    help.open()
  end, { buffer = M.bufnr, desc = "Open help popup" })
  vim.keymap.set("n", state.settings.discussion_tree.toggle_node, function()
    trees.toggle_node(M.tree)
  end, { buffer = M.bufnr, desc = "Toggle node" })
  vim.keymap.set("n", state.settings.discussion_tree.jump_to_file, function()
    common.jump_to_file(M.tree)
  end, { buffer = M.bufnr, desc = "Jump to file" })
  vim.keymap.set("n", state.settings.discussion_tree.jump_to_reviewer, function()
    common.jump_to_reviewer(M.tree, M.refresh_view)
  end, { buffer = M.bufnr, desc = "Jump to reviewer" })
  vim.keymap.set("n", state.settings.discussion_tree.open_in_browser, function()
    common.open_in_browser(M.tree) -- For some reason, I cannot see my own draft notes in Gitlab's UI
  end, { buffer = M.bufnr, desc = "Open the note in your browser" })
  vim.keymap.set("n", state.settings.discussion_tree.copy_node_url, function()
    common.copy_node_url(M.tree)
  end, { buffer = M.bufnr, desc = "Copy the URL of the current node to clipboard" })
  vim.keymap.set("n", "<leader>p", function()
    common.print_node()
  end, { buffer = M.bufnr, desc = "Print current node (for debugging)" })
  vim.keymap.set("n", state.settings.discussion_tree.toggle_all_discussions, function()
    local discussions = require("gitlab.actions.discussions")
    trees.toggle_nodes(discussions.split.winid, M.tree, false, {
      toggle_resolved = true,
      toggle_unresolved = true,
      keep_current_open = state.settings.discussion_tree.keep_current_open,
    })
  end, { buffer = M.bufnr, desc = "Toggle all nodes" })
end

---The edit_draft_note function lets the discussions module do the heavy lifting
---in order to handle the popup and keybindings.
M.edit_draft_note = function()
  require("gitlab.actions.discussions").edit_comment(M.tree, false)
end

---Send edits will actually send the edits to Gitlab and refresh the draft_notes tree
M.send_edits = function(note_id)
  return function(text)
    local body = { note = text }
    job.run_job(string.format("/mr/draft_notes/%d", note_id), "PATCH", body, function(data)
      u.notify(data.message, vim.log.levels.INFO)
      local new_draft_notes = List.new(state.DRAFT_NOTES)
          :map(function(note)
            if note.id == note_id then
              note.note = text
            end
            return note
          end)
      state.DRAFT_NOTES = new_draft_notes
      M.rebuild_draft_notes_tree()
    end)
  end
end

-- This function will actually send the deletion to Gitlab when you make a selection, and re-render the tree
M.send_deletion = function(tree)
  local current_node = tree:get_node()
  local note_node = common.get_note_node(tree, current_node)
  local root_node = common.get_root_node(tree, current_node)

  if note_node == nil or root_node == nil then
    u.notify("Could not get note or root node", vim.log.levels.ERROR)
    return
  end

  ---@type integer
  local note_id = note_node.is_root and root_node.id or note_node.id

  job.run_job(string.format("/mr/draft_notes/%d", note_id), "DELETE", nil, function(data)
    u.notify(data.message, vim.log.levels.INFO)
    local new_notes = List.new(state.DRAFT_NOTES)
        :filter(function(node)
          return node.id ~= note_id
        end)

    state.DRAFT_NOTES = new_notes
    M.rebuild_draft_notes_tree()
    M.refresh_view()
  end)
end

M.delete_draft_note = function(tree)
  vim.ui.select({ "Confirm", "Cancel" }, {
    prompt = "Delete comment?",
  }, function(choice)
    if choice == "Confirm" then
      M.send_deletion(tree)
    end
  end)
end

return M
