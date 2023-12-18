-- This module is responsible for the discussion tree. That includes things like
-- editing existing notes in the tree, replying to notes in the tree,
-- and marking discussions as resolved/unresolved.
local Split = require("nui.split")
local Popup = require("nui.popup")
local NuiTree = require("nui.tree")
local NuiLine = require("nui.line")
local job = require("gitlab.job")
local u = require("gitlab.utils")
local state = require("gitlab.state")
local reviewer = require("gitlab.reviewer")
local miscellaneous = require("gitlab.actions.miscellaneous")
local discussions_tree = require("gitlab.actions.discussions.tree")
local signs = require("gitlab.actions.discussions.signs")
local winbar = require("gitlab.actions.discussions.winbar")
local help = require("gitlab.actions.help")

local M = {
  split_visible = false,
  split = nil,
  ---@type number
  split_bufnr = nil,
  ---@type Discussion[]
  discussions = {},
  ---@type UnlinkedDiscussion[]
  unlinked_discussions = {},
  ---@type number
  linked_bufnr = nil,
  ---@type number
  unlinked_bufnr = nil,
  ---@type number
  focused_bufnr = nil,
  discussion_tree = nil,
}

---Makes API call to get the discussion data, store it in M.discussions and M.unlinked_discussions and call
---callback with data
---@param callback (fun(data: DiscussionData): nil)?
M.load_discussions = function(callback)
  job.run_job("/mr/discussions/list", "POST", { blacklist = state.settings.discussion_tree.blacklist }, function(data)
    M.discussions = data.discussions ~= vim.NIL and data.discussions or {}
    M.unlinked_discussions = data.unlinked_discussions ~= vim.NIL and data.unlinked_discussions or {}
    if type(callback) == "function" then
      callback(data)
    end
  end)
end

---Initialize everything for discussions like setup of signs, callbacks for reviewer, etc.
M.initialize_discussions = function()
  signs.setup_signs()
  -- Setup callback to refresh discussion data, discussion signs and diagnostics whenever the reviewed file changes.
  reviewer.set_callback_for_file_changed(M.refresh_discussion_data)
  -- Setup callback to clear signs and diagnostics whenever reviewer is left.
  reviewer.set_callback_for_reviewer_leave(signs.clear_signs_and_diagnostics)
end

---Refresh discussion data, signs, diagnostics, and winbar with new data from API
M.refresh_discussion_data = function()
  M.load_discussions(function()
    if state.settings.discussion_sign.enabled then
      signs.refresh_signs(M.discussions)
    end
    if state.settings.discussion_diagnostic.enabled then
      signs.refresh_diagnostics(M.discussions)
    end
    if M.split_visible then
      local linked_is_focused = M.linked_bufnr == M.focused_bufnr
      winbar.update_winbar(M.discussions, M.unlinked_discussions, linked_is_focused and "Discussions" or "Notes")
    end
  end)
end

---Opens the discussion tree, sets the keybindings. It also
---creates the tree for notes (which are not linked to specific lines of code)
---@param callback function?
M.toggle = function(callback)
  if M.split_visible then
    M.close()
    return
  end

  local split, linked_bufnr, unlinked_bufnr = M.create_split_and_bufs()
  M.linked_bufnr = linked_bufnr
  M.unlinked_bufnr = unlinked_bufnr

  M.split = split
  M.split_visible = true
  M.split_bufnr = split.bufnr
  split:mount()
  M.switch_can_edit_bufs(true)

  vim.api.nvim_buf_set_lines(split.bufnr, 0, -1, false, { "Loading data..." })
  vim.api.nvim_set_option_value("filetype", "gitlab", { buf = M.split_bufnr })
  vim.api.nvim_set_option_value("filetype", "gitlab", { buf = M.unlinked_bufnr })
  vim.api.nvim_set_option_value("filetype", "gitlab", { buf = M.linked_bufnr })

  local default_discussions = state.settings.discussion_tree.default_view == "discussions"
  winbar.update_winbar({}, {}, default_discussions and "Discussions" or "Notes")

  M.load_discussions(function()
    if type(M.discussions) ~= "table" and type(M.unlinked_discussions) ~= "table" then
      vim.notify("No discussions or notes for this MR", vim.log.levels.WARN)
      vim.api.nvim_buf_set_lines(split.bufnr, 0, -1, false, { "" })
      return
    end

    M.rebuild_discussion_tree()
    M.rebuild_unlinked_discussion_tree()
    M.add_empty_titles({
      { M.linked_bufnr,   M.discussions,          "No Discussions for this MR" },
      { M.unlinked_bufnr, M.unlinked_discussions, "No Notes (Unlinked Discussions) for this MR" },
    })

    local default_buffer = default_discussions and M.linked_bufnr or M.unlinked_bufnr
    vim.api.nvim_set_current_buf(default_buffer)
    M.focused_bufnr = default_buffer

    M.switch_can_edit_bufs(false)
    winbar.update_winbar(M.discussions, M.unlinked_discussions, default_discussions and "Discussions" or "Notes")
    if type(callback) == "function" then
      callback()
    end
  end)
end

local switch_view_type = function()
  local change_to_unlinked = M.linked_bufnr == M.focused_bufnr
  local new_bufnr = change_to_unlinked and M.unlinked_bufnr or M.linked_bufnr
  vim.api.nvim_set_current_buf(new_bufnr)
  winbar.update_winbar(M.discussions, M.unlinked_discussions, change_to_unlinked and "Notes" or "Discussions")
  M.focused_bufnr = new_bufnr
end

-- Clears the discussion state and unmounts the split
M.close = function()
  if M.split then
    M.split:unmount()
  end
  M.split_visible = false
  M.discussion_tree = nil
end

---Move to the discussion tree at the discussion from diagnostic on current line.
M.move_to_discussion_tree = function()
  local current_line = vim.api.nvim_win_get_cursor(0)[1]
  local diagnostics = vim.diagnostic.get(0, { namespace = signs.diagnostics_namespace, lnum = current_line - 1 })

  ---Function used to jump to the discussion tree after the menu selection.
  local jump_after_menu_selection = function(diagnostic)
    ---Function used to jump to the discussion tree after the discussion tree is opened.
    local jump_after_tree_opened = function()
      -- All diagnostics in `diagnotics_namespace` have diagnostic_id
      local discussion_id = diagnostic.user_data.discussion_id
      local discussion_node, line_number = M.discussion_tree:get_node("-" .. discussion_id)
      if discussion_node == {} or discussion_node == nil then
        vim.notify("Discussion not found", vim.log.levels.WARN)
        return
      end
      if not discussion_node:is_expanded() then
        for _, child in ipairs(discussion_node:get_child_ids()) do
          M.discussion_tree:get_node(child):expand()
        end
        discussion_node:expand()
      end
      M.discussion_tree:render()
      vim.api.nvim_win_set_cursor(M.split.winid, { line_number, 0 })
      vim.api.nvim_set_current_win(M.split.winid)
    end

    if not M.split_visible then
      M.toggle(jump_after_tree_opened)
    else
      jump_after_tree_opened()
    end
  end

  if #diagnostics == 0 then
    vim.notify("No diagnostics for this line", vim.log.levels.WARN)
    return
  elseif #diagnostics > 1 then
    vim.ui.select(diagnostics, {
      prompt = "Choose discussion to jump to",
      format_item = function(diagnostic)
        return diagnostic.message
      end,
    }, function(diagnostic)
      if not diagnostic then
        return
      end
      jump_after_menu_selection(diagnostic)
    end)
  else
    jump_after_menu_selection(diagnostics[1])
  end
end

-- The reply popup will mount in a window when you trigger it (settings.discussion_tree.reply) when hovering over a node in the discussion tree.
M.reply = function(tree)
  local reply_popup = Popup(u.create_popup_state("Reply", state.settings.popup.reply))
  local node = tree:get_node()
  local discussion_node = M.get_root_node(tree, node)
  local id = tostring(discussion_node.id)
  reply_popup:mount()
  state.set_popup_keymaps(reply_popup, M.send_reply(tree, id), miscellaneous.attach_file)
end

-- This function will send the reply to the Go API
M.send_reply = function(tree, discussion_id)
  return function(text)
    local body = { discussion_id = discussion_id, reply = text }
    job.run_job("/mr/reply", "POST", body, function(data)
      u.notify("Sent reply!", vim.log.levels.INFO)
      M.add_reply_to_tree(tree, data.note, discussion_id)
      M.load_discussions()
    end)
  end
end

-- This function (settings.discussion_tree.delete_comment) will trigger a popup prompting you to delete the current comment
M.delete_comment = function(tree, unlinked)
  vim.ui.select({ "Confirm", "Cancel" }, {
    prompt = "Delete comment?",
  }, function(choice)
    if choice == "Confirm" then
      M.send_deletion(tree, unlinked)
    end
  end)
end

-- This function will actually send the deletion to Gitlab
-- when you make a selection, and re-render the tree
M.send_deletion = function(tree, unlinked)
  local current_node = tree:get_node()

  local note_node = M.get_note_node(tree, current_node)
  local root_node = M.get_root_node(tree, current_node)
  local note_id = note_node.is_root and root_node.root_note_id or note_node.id

  local body = { discussion_id = root_node.id, note_id = tonumber(note_id) }

  job.run_job("/mr/comment", "DELETE", body, function(data)
    u.notify(data.message, vim.log.levels.INFO)
    if not note_node.is_root then
      tree:remove_node("-" .. note_id) -- Note is not a discussion root, safe to remove
      tree:render()
    else
      if unlinked then
        M.unlinked_discussions = u.remove_first_value(M.unlinked_discussions)
        M.rebuild_unlinked_discussion_tree()
      else
        M.discussions = u.remove_first_value(M.discussions)
        M.rebuild_discussion_tree()
      end
      M.add_empty_titles({
        { M.linked_bufnr,   M.discussions,          "No Discussions for this MR" },
        { M.unlinked_bufnr, M.unlinked_discussions, "No Notes (Unlinked Discussions) for this MR" },
      })
      M.switch_can_edit_bufs(false)
    end

    M.refresh_discussion_data()
  end)
end

-- This function (settings.discussion_tree.edit_comment) will open the edit popup for the current comment in the discussion tree
M.edit_comment = function(tree, unlinked)
  local edit_popup = Popup(u.create_popup_state("Edit Comment", state.settings.popup.edit))
  local current_node = tree:get_node()
  local note_node = M.get_note_node(tree, current_node)
  local root_node = M.get_root_node(tree, current_node)

  edit_popup:mount()

  local lines = {} -- Gather all lines from immediate children that aren't note nodes
  local children_ids = note_node:get_child_ids()
  for _, child_id in ipairs(children_ids) do
    local child_node = tree:get_node(child_id)
    if not child_node:has_children() then
      local line = tree:get_node(child_id).text
      table.insert(lines, line)
    end
  end

  local currentBuffer = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(currentBuffer, 0, -1, false, lines)
  state.set_popup_keymaps(
    edit_popup,
    M.send_edits(tostring(root_node.id), tonumber(note_node.root_note_id or note_node.id), unlinked)
  )
end

---This function sends the edited comment to the Go server
---@param discussion_id string
---@param note_id integer
---@param unlinked boolean
M.send_edits = function(discussion_id, note_id, unlinked)
  return function(text)
    local body = {
      discussion_id = discussion_id,
      note_id = note_id,
      comment = text,
    }
    job.run_job("/mr/comment", "PATCH", body, function(data)
      u.notify(data.message, vim.log.levels.INFO)
      M.rebuild_discussion_tree()
      if unlinked then
        M.replace_text(M.unlinked_discussions, discussion_id, note_id, text)
        M.rebuild_unlinked_discussion_tree()
      else
        M.replace_text(M.discussions, discussion_id, note_id, text)
        M.rebuild_discussion_tree()
      end
    end)
  end
end

-- This function (settings.discussion_tree.toggle_discussion_resolved) will toggle the resolved status of the current discussion and send the change to the Go server
M.toggle_discussion_resolved = function(tree)
  local note = tree:get_node()
  if not note or not note.resolvable then
    return
  end

  local body = {
    discussion_id = note.id,
    resolved = not note.resolved,
  }

  job.run_job("/mr/discussions/resolve", "PUT", body, function(data)
    u.notify(data.message, vim.log.levels.INFO)
    M.redraw_resolved_status(tree, note, not note.resolved)
    M.refresh_discussion_data()
  end)
end

-- This function (settings.discussion_tree.jump_to_reviewer) will jump the cursor to the reviewer's location associated with the note. The implementation depends on the reviewer
M.jump_to_reviewer = function(tree)
  local file_name, new_line, old_line, is_undefined_type, error = M.get_note_location(tree)
  if error ~= nil then
    u.notify(error, vim.log.levels.ERROR)
    return
  end
  reviewer.jump(file_name, new_line, old_line, { is_undefined_type = is_undefined_type })
end

-- This function (settings.discussion_tree.jump_to_file) will jump to the file changed in a new tab
M.jump_to_file = function(tree)
  local file_name, new_line, old_line, _, error = M.get_note_location(tree)
  if error ~= nil then
    u.notify(error, vim.log.levels.ERROR)
    return
  end
  vim.cmd.tabnew()
  u.jump_to_file(file_name, (new_line or old_line))
end

-- This function (settings.discussion_tree.toggle_node) expands/collapses the current node and its children
M.toggle_node = function(tree)
  local node = tree:get_node()
  if node == nil then
    return
  end
  local children = node:get_child_ids()
  if node == nil then
    return
  end
  if node:is_expanded() then
    node:collapse()
    if M.is_node_note(node) then
      for _, child in ipairs(children) do
        tree:get_node(child):collapse()
      end
    end
  else
    if M.is_node_note(node) then
      for _, child in ipairs(children) do
        tree:get_node(child):expand()
      end
    end
    node:expand()
  end

  tree:render()
end

--
-- 🌲 Helper Functions
--
---Inspired by default func https://github.com/MunifTanjim/nui.nvim/blob/main/lua/nui/tree/util.lua#L38
local function nui_tree_prepare_node(node)
  if not node.text then
    error("missing node.text")
  end

  local texts = node.text

  if type(node.text) ~= "table" or node.text.content then
    texts = { node.text }
  end

  local lines = {}

  for i, text in ipairs(texts) do
    local line = NuiLine()

    line:append(string.rep("  ", node._depth - 1))

    if i == 1 and node:has_children() then
      line:append(node:is_expanded() and " " or " ")
      if node.icon then
        line:append(node.icon .. " ", node.icon_hl)
      end
    else
      line:append("  ")
    end

    line:append(text, node.text_hl)

    table.insert(lines, line)
  end

  return lines
end

M.rebuild_discussion_tree = function()
  M.switch_can_edit_bufs(true)
  vim.api.nvim_buf_set_lines(M.linked_bufnr, 0, -1, false, {})
  local discussion_tree_nodes = discussions_tree.add_discussions_to_table(M.discussions, false)
  local discussion_tree =
      NuiTree({ nodes = discussion_tree_nodes, bufnr = M.linked_bufnr, prepare_node = nui_tree_prepare_node })
  discussion_tree:render()
  M.set_tree_keymaps(discussion_tree, M.linked_bufnr, false)
  M.discussion_tree = discussion_tree
  M.switch_can_edit_bufs(false)
  vim.api.nvim_set_option_value("filetype", "gitlab", { buf = M.linked_bufnr })
end

M.rebuild_unlinked_discussion_tree = function()
  M.switch_can_edit_bufs(true)
  vim.api.nvim_buf_set_lines(M.unlinked_bufnr, 0, -1, false, {})
  local unlinked_discussion_tree_nodes = discussions_tree.add_discussions_to_table(M.unlinked_discussions, true)
  local unlinked_discussion_tree = NuiTree({
    nodes = unlinked_discussion_tree_nodes,
    bufnr = M.unlinked_bufnr,
    prepare_node = nui_tree_prepare_node,
  })
  unlinked_discussion_tree:render()
  M.set_tree_keymaps(unlinked_discussion_tree, M.unlinked_bufnr, true)
  M.unlinked_discussion_tree = unlinked_discussion_tree
  M.switch_can_edit_bufs(false)
end

M.switch_can_edit_bufs = function(bool)
  u.switch_can_edit_buf(M.unlinked_bufnr, bool)
  u.switch_can_edit_buf(M.linked_bufnr, bool)
  vim.api.nvim_set_option_value("filetype", "gitlab", { buf = M.unlinked_bufnr })
  vim.api.nvim_set_option_value("filetype", "gitlab", { buf = M.linked_bufnr })
end

M.add_discussion = function(arg)
  local discussion = arg.data.discussion
  if arg.unlinked then
    if type(M.unlinked_discussions) ~= "table" then
      M.unlinked_discussions = {}
    end
    table.insert(M.unlinked_discussions, 1, discussion)
    M.rebuild_unlinked_discussion_tree()
    return
  end
  if type(M.discussions) ~= "table" then
    M.discussions = {}
  end
  table.insert(M.discussions, 1, discussion)
  M.rebuild_discussion_tree()
end

M.create_split_and_bufs = function()
  local position = state.settings.discussion_tree.position
  local size = state.settings.discussion_tree.size
  local relative = state.settings.discussion_tree.relative

  local split = Split({
    relative = relative,
    position = position,
    size = size,
  })

  local linked_bufnr = vim.api.nvim_create_buf(true, false)
  local unlinked_bufnr = vim.api.nvim_create_buf(true, false)

  return split, linked_bufnr, unlinked_bufnr
end

M.add_empty_titles = function(args)
  M.switch_can_edit_bufs(true)
  local ns_id = vim.api.nvim_create_namespace("GitlabNamespace")
  vim.cmd("highlight default TitleHighlight guifg=#787878")
  for _, section in ipairs(args) do
    local bufnr, data, title = section[1], section[2], section[3]
    if type(data) ~= "table" or #data == 0 then
      vim.api.nvim_buf_set_lines(bufnr, 0, 1, false, { title })
      local linnr = 1
      vim.api.nvim_buf_set_extmark(
        bufnr,
        ns_id,
        linnr - 1,
        0,
        { end_row = linnr - 1, end_col = string.len(title), hl_group = "TitleHighlight" }
      )
    end
  end
end

---Check if type of node is note or note body
---@param node NuiTree.Node?
---@return boolean
M.is_node_note = function(node)
  if node and (node.type == "note_body" or node.type == "note") then
    return true
  else
    return false
  end
end

---Check if type of current node is note or note body
---@param tree NuiTree
---@return boolean
M.is_current_node_note = function(tree)
  return M.is_node_note(tree:get_node())
end

M.set_tree_keymaps = function(tree, bufnr, unlinked)
  vim.keymap.set("n", state.settings.discussion_tree.edit_comment, function()
    if M.is_current_node_note(tree) then
      M.edit_comment(tree, unlinked)
    end
  end, { buffer = bufnr, desc = "Edit comment" })
  vim.keymap.set("n", state.settings.discussion_tree.delete_comment, function()
    if M.is_current_node_note(tree) then
      M.delete_comment(tree, unlinked)
    end
  end, { buffer = bufnr, desc = "Delete comment" })
  vim.keymap.set("n", state.settings.discussion_tree.toggle_resolved, function()
    if M.is_current_node_note(tree) then
      M.toggle_discussion_resolved(tree)
    end
  end, { buffer = bufnr, desc = "Toggle resolved" })
  vim.keymap.set("n", state.settings.discussion_tree.toggle_node, function()
    M.toggle_node(tree)
  end, { buffer = bufnr, desc = "Toggle node" })
  vim.keymap.set("n", state.settings.discussion_tree.reply, function()
    if M.is_current_node_note(tree) then
      M.reply(tree)
    end
  end, { buffer = bufnr, desc = "Reply" })
  vim.keymap.set("n", state.settings.discussion_tree.switch_view, function()
    switch_view_type()
  end, { buffer = bufnr, desc = "Switch view type" })
  vim.keymap.set("n", state.settings.help, function()
    help.open()
  end, { buffer = bufnr, desc = "Open help popup" })
  if not unlinked then
    vim.keymap.set("n", state.settings.discussion_tree.jump_to_file, function()
      if M.is_current_node_note(tree) then
        M.jump_to_file(tree)
      end
    end, { buffer = bufnr, desc = "Jump to file" })
    vim.keymap.set("n", state.settings.discussion_tree.jump_to_reviewer, function()
      if M.is_current_node_note(tree) then
        M.jump_to_reviewer(tree)
      end
    end, { buffer = bufnr, desc = "Jump to reviewer" })
  end
  vim.keymap.set("n", state.settings.discussion_tree.open_in_browser, function()
    M.open_in_browser(tree)
  end, { buffer = bufnr, desc = "Open the note in your browser" })
  vim.keymap.set("n", "<leader>p", function()
    M.print_node(tree)
  end, { buffer = bufnr, desc = "dev_ Print current node (for debugging)" })
end

M.redraw_resolved_status = function(tree, note, mark_resolved)
  local current_text = tree.nodes.by_id["-" .. note.id].text
  local target = mark_resolved and "resolved" or "unresolved"
  local current = mark_resolved and "unresolved" or "resolved"

  local function set_property(key, val)
    tree.nodes.by_id["-" .. note.id][key] = val
  end

  local has_symbol = function(s)
    return state.settings.discussion_tree[s] ~= nil and state.settings.discussion_tree[s] ~= ""
  end

  set_property("resolved", mark_resolved)

  if not has_symbol(current) and not has_symbol(target) then
    return
  end

  if not has_symbol(current) and has_symbol(target) then
    set_property("text", (current_text .. " " .. state.settings.discussion_tree[target]))
  elseif has_symbol(current) and not has_symbol(target) then
    set_property("text", u.remove_last_chunk(current_text))
  else
    set_property("text", (u.remove_last_chunk(current_text) .. " " .. state.settings.discussion_tree[target]))
  end

  tree:render()
end

---Replace text in discussion after note update.
---@param data Discussion[]|UnlinkedDiscussion[]
---@param discussion_id string
---@param note_id integer
---@param text string
M.replace_text = function(data, discussion_id, note_id, text)
  for i, discussion in ipairs(data) do
    if discussion.id == discussion_id then
      for j, note in ipairs(discussion.notes) do
        if note.id == note_id then
          data[i].notes[j].body = text
        end
      end
    end
  end
end

---Get root node
---@param tree NuiTree
---@param node NuiTree.Node?
---@return NuiTree.Node?
M.get_root_node = function(tree, node)
  if not node then
    return nil
  end
  if node.type == "note_body" or node.type == "note" and not node.is_root then
    local parent_id = node:get_parent_id()
    return M.get_root_node(tree, tree:get_node(parent_id))
  elseif node.is_root then
    return node
  end
end

---Get note node
---@param tree NuiTree
---@param node NuiTree.Node?
---@return NuiTree.Node?
M.get_note_node = function(tree, node)
  if not node then
    return nil
  end

  if node.type == "note_body" then
    local parent_id = node:get_parent_id()
    if parent_id == nil then
      return node
    end
    return M.get_note_node(tree, tree:get_node(parent_id))
  elseif node.type == "note" then
    return node
  end
end

M.add_reply_to_tree = function(tree, note, discussion_id)
  local note_node = discussions_tree.build_note(note)
  note_node:expand()
  tree:add_node(note_node, discussion_id and ("-" .. discussion_id) or nil)
  tree:render()
end

---Get note location
---@param tree NuiTree
---@return string, string, string, boolean, string?
M.get_note_location = function(tree)
  local node = tree:get_node()
  if node == nil then
    return "", "", "", false, "Could not get node"
  end
  local discussion_node = M.get_root_node(tree, node)
  if discussion_node == nil then
    return "", "", "", false, "Could not get discussion node"
  end
  return discussion_node.file_name,
      discussion_node.new_line,
      discussion_node.old_line,
      discussion_node.undefined_type or false,
      nil
end

---@param tree NuiTree
M.open_in_browser = function(tree)
  local current_node = tree:get_node()
  local note_node = M.get_note_node(tree, current_node)
  if note_node == nil then
    return
  end
  local url = note_node.url
  if url == nil then
    u.notify("Could not get URL of note", vim.log.levels.ERROR)
    return
  end

  u.open_in_browser(url)
end

-- For developers!
M.print_node = function(tree)
  local current_node = tree:get_node()
  vim.print(current_node)
end

return M
