-- This module is responsible for the discussion tree. That includes things like
-- editing existing notes in the tree, replying to notes in the tree,
-- and marking discussions as resolved/unresolved.
local Split        = require("nui.split")
local Popup        = require("nui.popup")
local Menu         = require("nui.menu")
local NuiTree      = require("nui.tree")
local Layout       = require("nui.layout")
local job          = require("gitlab.job")
local u            = require("gitlab.utils")
local state        = require("gitlab.state")
local reviewer     = require("gitlab.reviewer")

local edit_popup   = Popup(u.create_popup_state("Edit Comment", "80%", "80%"))
local reply_popup  = Popup(u.create_popup_state("Reply", "80%", "80%"))

local M            = {
  layout_visible = false,
  layout = nil,
  layout_buf = nil,
  discussions = {},
  unlinked_discussions = {},
  linked_section_bufnr = -1,
  unlinked_section_bufnr = -1,
}

-- Opens the discussion tree, sets the keybindings. It also
-- creates the tree for notes (which are not linked to specific lines of code)
M.toggle           = function()
  if M.layout_visible then
    M.layout:unmount()
    M.layout_visible = false
    return
  end

  local linked_section, unlinked_section, layout = M.create_layout()
  M.linked_section_bufnr = linked_section.bufnr
  M.unlinked_section_bufnr = unlinked_section.bufnr

  job.run_job("/discussions", "POST", { blacklist = state.settings.discussion_tree.blacklist }, function(data)
    if type(data.discussions) ~= "table" and type(data.unlinked_discussions) ~= "table" then
      vim.notify("No discussions or notes for this MR", vim.log.levels.WARN)
      return
    end

    layout:mount()
    layout:show()

    M.layout = layout
    M.layout_visible = true
    M.layout_buf = layout.bufnr
    state.discussion_buf = layout.bufnr

    M.discussions = data.discussions
    M.unlinked_discussions = data.unlinked_discussions

    if type(data.discussions) == "table" then M.rebuild_discussion_tree() end
    if type(data.unlinked_discussions) == "table" then M.rebuild_unlinked_discussion_tree() end

    M.add_empty_titles({
      { linked_section.bufnr,   data.discussions,          "No Discussions for this MR" },
      { unlinked_section.bufnr, data.unlinked_discussions, "No Notes (Unlinked Discussions) for this MR" }
    })
  end)
end

-- The reply popup will mount in a window when you trigger it (settings.discussion_tree.reply) when hovering over a node in the discussion tree.
M.reply            = function(tree)
  local node = tree:get_node()
  local discussion_node = M.get_root_node(tree, node)
  local id = tostring(discussion_node.id)
  reply_popup:mount()
  state.set_popup_keymaps(reply_popup, M.send_reply(tree, id))
end

-- This function will send the reply to the Go API
M.send_reply       = function(tree, discussion_id)
  return function(text)
    local body = { discussion_id = discussion_id, reply = text }
    job.run_job("/reply", "POST", body, function(data)
      vim.notify("Sent reply!", vim.log.levels.INFO)
      M.add_reply_to_tree(tree, data.note, discussion_id)
    end)
  end
end

-- This function (settings.discussion_tree.delete_comment) will trigger a popup prompting you to delete the current comment
M.delete_comment   = function(tree, unlinked)
  local menu = Menu({
    position = "50%",
    size = {
      width = 25,
    },
    border = {
      style = "single",
      text = {
        top = "Delete Comment?",
        top_align = "center",
      },
    },
    win_options = {
      winhighlight = "Normal:Normal,FloatBorder:Normal",
    },
  }, {
    lines = {
      Menu.item("Confirm"),
      Menu.item("Cancel"),
    },
    max_width = 20,
    keymap = {
      focus_next = state.settings.dialogue.focus_next,
      focus_prev = state.settings.dialogue.focus_prev,
      close = state.settings.dialogue.close,
      submit = state.settings.dialogue.submit,
    },
    on_submit = function(item)
      M.send_deletion(tree, item, unlinked)
    end
  })
  menu:mount()
end

-- This function will actually send the deletion to Gitlab
-- when you make a selection, and re-render the tree
M.send_deletion    = function(tree, item, unlinked)
  if item.text == "Confirm" then
    local current_node = tree:get_node()

    local note_node = M.get_note_node(tree, current_node)
    local root_node = M.get_root_node(tree, current_node)
    local note_id = note_node.is_root and root_node.root_note_id or note_node.id

    local body = { discussion_id = root_node.id, note_id = note_id }

    job.run_job("/comment", "DELETE", body, function(data)
      vim.notify(data.message, vim.log.levels.INFO)
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
      end
    end)
  end
end

-- This function (settings.discussion_tree.edit_comment) will open the edit popup for the current comment in the discussion tree
M.edit_comment     = function(tree)
  local current_node = tree:get_node()
  local note_node = M.get_note_node(tree, current_node)
  local root_node = M.get_root_node(tree, current_node)

  edit_popup:mount()

  local lines = {} -- Gather all lines from immediate children that aren't note nodes
  local children_ids = note_node:get_child_ids()
  for _, child_id in ipairs(children_ids) do
    local child_node = tree:get_node(child_id)
    if (not child_node:has_children()) then
      local line = tree:get_node(child_id).text
      table.insert(lines, line)
    end
  end

  local currentBuffer = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(currentBuffer, 0, -1, false, lines)
  state.set_popup_keymaps(edit_popup, M.send_edits(tree, tostring(root_node.id), note_node.root_note_id or note_node.id))
end

-- This function sends the edited comment to the Go server
M.send_edits       = function(tree, discussion_id, note_id)
  return function(text)
    local body = {
      discussion_id = discussion_id,
      note_id = note_id,
      comment = text
    }
    job.run_job("/comment", "PATCH", body, function(data)
      vim.notify(data.message, vim.log.levels.INFO)
      M.redraw_text(tree, text)
    end)
  end
end

-- This comment (settings.discussion_tree.toggle_resolved) will toggle the resolved status of the current discussion and send the change to the Go server
M.toggle_resolved  = function(tree)
  local note = tree:get_node()
  if not note or not note.resolvable then return end

  local body = {
    discussion_id = note.id,
    note_id = note.root_note_id,
    resolved = not note.resolved,
  }

  job.run_job("/comment", "PATCH", body, function(data)
    vim.notify(data.message, vim.log.levels.INFO)
    M.redraw_resolved_status(tree, note, not note.resolved)
  end)
end

-- This function (settings.discussion_tree.jump_to_reviewer) will jump the cursor to the reviewer's location associated with the note. The implementation depends on the reviewer
M.jump_to_reviewer = function(tree)
  local file_name, new_line, old_line, error = M.get_note_location(tree)
  if error ~= nil then
    vim.notify(error, vim.log.levels.ERROR)
    return
  end
  reviewer.jump(file_name, new_line, old_line)
end

-- This function (settings.discussion_tree.jump_to_file) will jump to the file changed in a new tab
M.jump_to_file     = function(tree)
  local file_name, new_line, old_line, error = M.get_note_location(tree)
  if error ~= nil then
    vim.notify(error, vim.log.levels.ERROR)
    return
  end
  vim.cmd.tabnew()
  u.jump_to_file(file_name, (new_line or old_line))
end

-- This function (settings.discussion_tree.toggle_node) expands/collapses the current node and its children
M.toggle_node      = function(tree)
  local node = tree:get_node()
  if node == nil then return end
  local children = node:get_child_ids()
  if node == nil then return end
  if node:is_expanded() then
    node:collapse()
    for _, child in ipairs(children) do
      tree:get_node(child):collapse()
    end
  else
    for _, child in ipairs(children) do
      tree:get_node(child):expand()
    end
    node:expand()
  end

  tree:render()
end


--
-- 🌲 Helper Functions
--

M.rebuild_discussion_tree          = function()
  vim.api.nvim_buf_set_option(M.linked_section_bufnr, 'modifiable', true)
  vim.api.nvim_buf_set_option(M.linked_section_bufnr, "readonly", false)
  vim.api.nvim_buf_set_lines(M.linked_section_bufnr, 0, -1, false, {})
  local discussion_tree_nodes = M.add_discussions_to_table(M.discussions)
  local discussion_tree = NuiTree({ nodes = discussion_tree_nodes, bufnr = M.linked_section_bufnr })
  discussion_tree:render()
  M.set_tree_keymaps(discussion_tree, M.linked_section_bufnr, false)
  M.discussion_tree = discussion_tree
  vim.api.nvim_buf_set_option(M.linked_section_bufnr, 'modifiable', false)
  vim.api.nvim_buf_set_option(M.linked_section_bufnr, "readonly", true)
end

M.rebuild_unlinked_discussion_tree = function()
  vim.api.nvim_buf_set_option(M.unlinked_section_bufnr, 'modifiable', true)
  vim.api.nvim_buf_set_option(M.unlinked_section_bufnr, "readonly", false)
  vim.api.nvim_buf_set_lines(M.unlinked_section_bufnr, 0, -1, false, {})
  local unlinked_discussion_tree_nodes = M.add_discussions_to_table(M.unlinked_discussions)
  local unlinked_discussion_tree = NuiTree({ nodes = unlinked_discussion_tree_nodes, bufnr = M.unlinked_section_bufnr })
  unlinked_discussion_tree:render()
  M.set_tree_keymaps(unlinked_discussion_tree, M.unlinked_section_bufnr, true)
  M.unlinked_discussion_tree = unlinked_discussion_tree
  vim.api.nvim_buf_set_option(M.unlinked_section_bufnr, 'modifiable', false)
  vim.api.nvim_buf_set_option(M.unlinked_section_bufnr, "readonly", true)
end

M.add_discussion                   = function(arg)
  local discussion = arg.data.discussion
  if arg.unlinked then
    if type(M.unlinked_discussions) ~= "table" then M.unlinked_discussions = {} end
    table.insert(M.unlinked_discussions, 1, discussion)
    local bufinfo = vim.fn.getbufinfo(M.unlinked_section_bufnr)
    if u.table_size(bufinfo) ~= 0 then
      M.rebuild_unlinked_discussion_tree()
    end
    return
  end
  if type(M.discussions) ~= "table" then M.discussions = {} end
  table.insert(M.discussions, 1, discussion)
  local bufinfo = vim.fn.getbufinfo(M.unlinked_section_bufnr)
  if u.table_size(bufinfo) ~= 0 then
    M.rebuild_discussion_tree()
  end
end

M.create_layout                    = function()
  local linked_section   = Split({ enter = true })
  local unlinked_section = Split({})

  local position         = state.settings.discussion_tree.position
  local size             = state.settings.discussion_tree.size
  local relative         = state.settings.discussion_tree.relative

  local layout           = Layout(
    {
      position = position,
      size = size,
      relative = relative,
    },
    Layout.Box({
        Layout.Box(linked_section, { size = "50%" }),
        Layout.Box(unlinked_section, { size = "50%" }),
      },
      { dir = (position == "left" and "col" or "row") }
    )
  )

  return linked_section, unlinked_section, layout
end

M.add_empty_titles                 = function(args)
  local ns_id = vim.api.nvim_create_namespace("GitlabNamespace")
  vim.cmd("highlight default TitleHighlight guifg=#787878")
  for _, section in ipairs(args) do
    local bufnr, data, title = section[1], section[2], section[3]
    if data == nil then
      print(bufnr, title)
      vim.api.nvim_buf_set_lines(bufnr, 0, 1, false, { title })
      local linnr = 1
      vim.api.nvim_buf_set_extmark(bufnr, ns_id, linnr - 1, 0,
        { end_row = linnr - 1, end_col = string.len(title), hl_group = 'TitleHighlight' })
    end
  end
end

M.set_tree_keymaps                 = function(tree, bufnr, unlinked)
  vim.keymap.set('n',
    state.settings.discussion_tree.edit_comment,
    function() M.edit_comment(tree) end,
    { buffer = bufnr }
  )
  vim.keymap.set('n',
    state.settings.discussion_tree.delete_comment,
    function() M.delete_comment(tree, unlinked) end,
    { buffer = bufnr }
  )
  vim.keymap.set('n',
    state.settings.discussion_tree.toggle_resolved,
    function() M.toggle_resolved(tree) end,
    { buffer = bufnr }
  )
  vim.keymap.set('n',
    state.settings.discussion_tree.toggle_node,
    function() M.toggle_node(tree) end,
    { buffer = bufnr }
  )
  vim.keymap.set('n',
    state.settings.discussion_tree.reply,
    function() M.reply(tree) end,
    { buffer = bufnr }
  )

  if not unlinked then
    vim.keymap.set('n', state.settings.discussion_tree.jump_to_file, function()
      M.jump_to_file(tree)
    end, { buffer = bufnr }
    )
    vim.keymap.set('n', state.settings.discussion_tree.jump_to_reviewer,
      function() M.jump_to_reviewer(tree) end,
      { buffer = bufnr }
    )
  end
end


M.redraw_resolved_status = function(tree, note, mark_resolved)
  local current_text = tree.nodes.by_id["-" .. note.id].text
  local target = mark_resolved and 'resolved' or 'unresolved'
  local current = mark_resolved and 'unresolved' or 'resolved'

  local function set_property(key, val)
    tree.nodes.by_id["-" .. note.id][key] = val
  end

  local has_symbol = function(s)
    return state.settings.discussion_tree[s] ~= nil and state.settings.discussion_tree[s] ~= ''
  end

  set_property('resolved', mark_resolved)

  if not has_symbol(current) and not has_symbol(target) then return end

  if not has_symbol(current) and has_symbol(target) then
    set_property('text', (current_text .. " " .. state.settings.discussion_tree[target]))
  elseif has_symbol(current) and not has_symbol(target) then
    set_property('text', u.remove_last_chunk(current_text))
  else
    set_property('text', (u.remove_last_chunk(current_text) .. " " .. state.settings.discussion_tree[target]))
  end

  tree:render()
end

M.redraw_text            = function(tree, text)
  local current_node = tree:get_node()
  local note_node = M.get_note_node(tree, current_node)

  local childrenIds = note_node:get_child_ids()
  for _, value in ipairs(childrenIds) do
    tree:remove_node(value)
  end

  local newNoteTextNodes = {}
  for bodyLine in text:gmatch("[^\n]+") do
    table.insert(newNoteTextNodes, NuiTree.Node({ text = bodyLine, is_body = true }, {}))
  end

  tree:set_nodes(newNoteTextNodes, "-" .. note_node.id)
  tree:render()
end

M.get_root_node          = function(tree, node)
  if (not node.is_root) then
    local parent_id = node:get_parent_id()
    return M.get_root_node(tree, tree:get_node(parent_id))
  else
    return node
  end
end

M.get_note_node          = function(tree, node)
  if (not node.is_note) then
    local parent_id = node:get_parent_id()
    if parent_id == nil then return node end
    return M.get_note_node(tree, tree:get_node(parent_id))
  else
    return node
  end
end

local attach_uuid        = function(str)
  return { text = str, id = u.uuid() }
end

M.build_note_body        = function(note, resolve_info)
  local text_nodes = {}
  for bodyLine in note.body:gmatch("[^\n]+") do
    local line = attach_uuid(bodyLine)
    table.insert(text_nodes, NuiTree.Node({
      new_line = (type(note.position) == "table" and note.position.new_line),
      old_line = (type(note.position) == "table" and note.position.old_line),
      text = line.text,
      id = line.id,
      is_body = true
    }, {}))
  end

  local resolve_symbol = ''
  if resolve_info ~= nil and resolve_info.resolvable then
    resolve_symbol = resolve_info.resolved and state.settings.discussion_tree.resolved or
        state.settings.discussion_tree.unresolved
  end

  local noteHeader = "@" .. note.author.username .. " " .. u.format_date(note.created_at) .. " " .. resolve_symbol

  return noteHeader, text_nodes
end

M.build_note             = function(note, resolve_info)
  local text, text_nodes = M.build_note_body(note, resolve_info)
  local note_node = NuiTree.Node({
    text = text,
    id = note.id,
    file_name = (type(note.position) == "table" and note.position.new_path),
    new_line = (type(note.position) == "table" and note.position.new_line),
    old_line = (type(note.position) == "table" and note.position.old_line),
    is_note = true,
  }, text_nodes)

  return note_node, text, text_nodes
end

M.add_reply_to_tree      = function(tree, note, discussion_id)
  local note_node = M.build_note(note)
  note_node:expand()
  tree:add_node(note_node, discussion_id and ("-" .. discussion_id) or nil)
  tree:render()
end


M.add_discussions_to_table = function(items)
  local t = {}
  for _, discussion in ipairs(items) do
    local discussion_children = {}

    -- These properties are filled in by the first note
    local root_text = ''
    local root_note_id = ''
    local root_file_name = ''
    local root_id = 0
    local root_text_nodes = {}
    local resolvable = false
    local resolved = false
    local root_new_line = nil
    local root_old_line = nil

    for j, note in ipairs(discussion.notes) do
      if j == 1 then
        __, root_text, root_text_nodes = M.build_note(note, { resolved = note.resolved, resolvable = note.resolvable })

        root_file_name = (type(note.position) == "table" and note.position.new_path)
        root_new_line = (type(note.position) == "table" and note.position.new_line)
        root_old_line = (type(note.position) == "table" and note.position.old_line)
        root_id = discussion.id
        root_note_id = note.id
        resolvable = note.resolvable
        resolved = note.resolved
      else -- Otherwise insert it as a child node...
        local note_node = M.build_note(note)
        table.insert(discussion_children, note_node)
      end
    end

    -- Creates the first node in the discussion, and attaches children
    local body = u.join_tables(root_text_nodes, discussion_children)
    local root_node = NuiTree.Node({
      text = root_text,
      is_note = true,
      is_root = true,
      id = root_id,
      root_note_id = root_note_id,
      file_name = root_file_name,
      new_line = root_new_line,
      old_line = root_old_line,
      resolvable = resolvable,
      resolved = resolved
    }, body)

    table.insert(t, root_node)
  end

  return t
end

M.get_note_location        = function(tree)
  local node = tree:get_node()
  if node == nil then return nil, nil, nil, "Could not get node" end
  local discussion_node = M.get_root_node(tree, node)
  if discussion_node == nil then return nil, nil, nil, "Could not get discussion node" end
  return discussion_node.file_name, discussion_node.new_line, discussion_node.old_line
end

return M
