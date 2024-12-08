-- This module contains tree code specific to the discussion tree, that
-- is not used in the draft notes tree
local u = require("gitlab.utils")
local common = require("gitlab.actions.common")
local List = require("gitlab.utils.list")
local state = require("gitlab.state")
local NuiTree = require("nui.tree")
local NuiLine = require("nui.line")

local M = {}

---Create nodes for NuiTree from discussions
---@param items Discussion[]
---@param unlinked boolean? False or nil means that discussions are linked to code lines
---@return NuiTree.Node[]
M.add_discussions_to_table = function(items, unlinked)
  local t = {}
  if items == vim.NIL then
    items = {}
  end
  for _, discussion in ipairs(items) do
    local discussion_children = {}

    -- These properties are filled in by the first note
    ---@type string?
    local root_text = ""
    ---@type string?
    local root_note_id = ""
    ---@type string?
    local root_file_name = ""
    ---@type string
    local root_id
    local root_text_nodes = {}
    local resolvable = false
    ---@type GitlabLineRange|nil
    local range = nil
    local resolved = false
    local root_new_line = nil
    local root_old_line = nil
    local root_url

    for j, note in ipairs(discussion.notes) do
      if j == 1 then
        _, root_text, root_text_nodes = M.build_note(note, { resolved = note.resolved, resolvable = note.resolvable })
        root_file_name = (type(note.position) == "table" and note.position.new_path or nil)
        root_new_line = (type(note.position) == "table" and note.position.new_line or nil)
        root_old_line = (type(note.position) == "table" and note.position.old_line or nil)
        root_id = discussion.id
        root_note_id = tostring(note.id)
        resolvable = note.resolvable
        resolved = note.resolved
        root_url = state.INFO.web_url .. "#note_" .. note.id
        range = (type(note.position) == "table" and note.position.line_range or nil)
      else -- Otherwise insert it as a child node...
        local note_node = M.build_note(note)
        table.insert(discussion_children, note_node)
      end
    end

    -- Attaches draft notes that are replies to their parent discussions
    local draft_replies = List.new(state.DRAFT_NOTES or {})
      :filter(function(note)
        return note.discussion_id == discussion.id
      end)
      :map(function(note)
        local result = M.build_note(note)
        return result
      end)

    local all_children = u.join(discussion_children, draft_replies)

    -- Creates the first node in the discussion, and attaches children
    local body = u.spread(root_text_nodes, all_children)
    local root_node = NuiTree.Node({
      range = range,
      text = root_text,
      type = "note",
      is_root = true,
      id = root_id,
      root_note_id = root_note_id,
      file_name = root_file_name,
      new_line = root_new_line,
      old_line = root_old_line,
      resolvable = resolvable,
      resolved = resolved,
      url = root_url,
    }, body)

    table.insert(t, root_node)
  end
  if state.settings.discussion_tree.tree_type == "simple" or unlinked == true then
    return t
  end

  return M.create_node_list_by_file_name(t)
end

---Create path node
---@param relative_path string
---@param full_path string
---@param child_nodes NuiTree.Node[]?
---@return NuiTree.Node
local function create_path_node(relative_path, full_path, child_nodes)
  return NuiTree.Node({
    text = relative_path,
    path = full_path,
    id = full_path,
    type = "path",
    icon = " ",
    icon_hl = "GitlabDirectoryIcon",
    text_hl = "GitlabDirectory",
  }, child_nodes or {})
end

---Sort list of nodes (in place) of type "path" or "file_name"
---@param nodes NuiTree.Node[]
local function sort_nodes(nodes)
  table.sort(nodes, function(node1, node2)
    if node1.type == "path" and node2.type == "path" then
      return node1.path < node2.path
    elseif node1.type == "file_name" and node2.type == "file_name" then
      return node1.file_name < node2.file_name
    elseif node1.type == "path" and node2.type == "file_name" then
      return true
    else
      return false
    end
  end)
end

---Merge path nodes which have only single path child
---@param node NuiTree.Node
local function flatten_nodes(node)
  if node.type ~= "path" then
    return
  end
  for _, child in ipairs(node.__children) do
    flatten_nodes(child)
  end
  if #node.__children == 1 and node.__children[1].type == "path" then
    local child = node.__children[1]
    node.__children = child.__children
    node.id = child.id
    node.path = child.path
    node.text = node.text .. u.path_separator .. child.text
  end
  sort_nodes(node.__children)
end

---Create file name node
---@param file_name string
---@param full_file_path string
---@param child_nodes NuiTree.Node[]?
---@return NuiTree.Node
local function create_file_name_node(file_name, full_file_path, child_nodes)
  local icon, icon_hl = u.get_icon(file_name)
  return NuiTree.Node({
    text = file_name,
    file_name = full_file_path,
    id = full_file_path,
    type = "file_name",
    icon = icon,
    icon_hl = icon_hl,
    text_hl = "GitlabFileName",
  }, child_nodes or {})
end

local create_disscussions_by_file_name = function(node_list)
  -- Create all the folder and file name nodes.
  local discussion_by_file_name = {}
  local top_level_path_to_node = {}

  for _, node in ipairs(node_list) do
    local path = ""
    local parent_node = nil
    local path_parts = u.split_path(node.file_name)
    local file_name = table.remove(path_parts, #path_parts)
    -- Create folders
    for i, path_part in ipairs(path_parts) do
      path = path ~= nil and path .. u.path_separator .. path_part or path_part
      if i == 1 then
        if top_level_path_to_node[path] == nil then
          parent_node = create_path_node(path_part, path)
          top_level_path_to_node[path] = parent_node
          table.insert(discussion_by_file_name, parent_node)
        end
        parent_node = top_level_path_to_node[path]
      elseif parent_node then
        local child_node = nil
        for _, child in ipairs(parent_node.__children) do
          if child.path == path then
            child_node = child
            break
          end
        end

        if child_node == nil then
          child_node = create_path_node(path_part, path)
          table.insert(parent_node.__children, child_node)
          parent_node:expand()
          parent_node = child_node
        else
          parent_node = child_node
        end
      end
    end

    -- Create file name nodes
    if parent_node == nil then
      ---Top level file name
      if top_level_path_to_node[node.file_name] ~= nil then
        table.insert(top_level_path_to_node[node.file_name].__children, node)
      else
        local file_node = create_file_name_node(file_name, node.file_name, { node })
        file_node:expand()
        top_level_path_to_node[node.file_name] = file_node
        table.insert(discussion_by_file_name, file_node)
      end
    else
      local child_node = nil
      for _, child in ipairs(parent_node.__children) do
        if child.file_name == node.file_name then
          child_node = child
          break
        end
      end
      if child_node == nil then
        child_node = create_file_name_node(file_name, node.file_name, { node })
        table.insert(parent_node.__children, child_node)
        parent_node:expand()
        child_node:expand()
      else
        table.insert(child_node.__children, node)
      end
    end
  end

  return discussion_by_file_name
end

M.create_node_list_by_file_name = function(node_list)
  -- Create all the folder and file name nodes.
  local discussion_by_file_name = create_disscussions_by_file_name(node_list)

  -- Flatten empty folders
  for _, node in ipairs(discussion_by_file_name) do
    flatten_nodes(node)
  end

  sort_nodes(discussion_by_file_name)

  return discussion_by_file_name
end

local attach_uuid = function(str)
  return { text = str, id = u.uuid() }
end

---Build note node body
---@param note Note|DraftNote
---@param resolve_info table?
---@return string
---@return NuiTree.Node[]
local function build_note_body(note, resolve_info)
  local text_nodes = {}
  for bodyLine in u.split_by_new_lines(note.body or note.note) do
    local line = attach_uuid(bodyLine)
    table.insert(
      text_nodes,
      NuiTree.Node({
        new_line = (type(note.position) == "table" and note.position.new_line),
        old_line = (type(note.position) == "table" and note.position.old_line),
        text = line.text,
        id = line.id,
        type = "note_body",
      }, {})
    )
  end

  local symbol = ""
  local is_draft = note.note ~= nil
  if resolve_info ~= nil and resolve_info.resolvable then
    symbol = resolve_info.resolved and state.settings.discussion_tree.resolved
      or state.settings.discussion_tree.unresolved
  elseif not is_draft and resolve_info and not resolve_info.resolvable then
    symbol = state.settings.discussion_tree.unlinked
  end

  local noteHeader = common.build_note_header(note) .. " " .. symbol

  return noteHeader, text_nodes
end

---Build note node
---@param note Note|DraftNote
---@param resolve_info table?
---@return NuiTree.Node
---@return string
---@return NuiTree.Node[]
M.build_note = function(note, resolve_info)
  local text, text_nodes = build_note_body(note, resolve_info)
  local note_node = NuiTree.Node({
    text = text,
    is_draft = note.note ~= nil,
    id = note.id,
    file_name = (type(note.position) == "table" and note.position.new_path),
    new_line = (type(note.position) == "table" and note.position.new_line),
    old_line = (type(note.position) == "table" and note.position.old_line),
    url = state.INFO.web_url .. "#note_" .. note.id,
    type = "note",
  }, text_nodes)

  return note_node, text, text_nodes
end

---Inspired by default func https://github.com/MunifTanjim/nui.nvim/blob/main/lua/nui/tree/util.lua#L38
M.nui_tree_prepare_node = function(node)
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
    local expanders = state.settings.discussion_tree.expanders

    line:append(string.rep(expanders.indentation, node._depth - 1))

    if i == 1 and node:has_children() then
      line:append(node:is_expanded() and expanders.expanded or expanders.collapsed)
      if node.icon then
        line:append(node.icon .. " ", node.icon_hl)
      end
    else
      line:append(expanders.indentation)
    end

    line:append(text, node.text_hl)

    local note_id = tostring(node.is_root and node.root_note_id or node.id)

    local e = require("gitlab.emoji")

    ---@type Emoji[]
    local emojis = state.DISCUSSION_DATA.emojis[note_id]
    local placed_emojis = {}
    if emojis ~= nil then
      for _, v in ipairs(emojis) do
        local icon = e.emoji_map[v.name]
        if icon ~= nil and not u.contains(placed_emojis, icon.moji) then
          line:append(" ")
          line:append(icon.moji)
          table.insert(placed_emojis, icon.moji)
        end
      end
    end

    table.insert(lines, line)
  end

  return lines
end

---@class ToggleNodesOptions
---@field toggle_resolved boolean Whether to toggle resolved discussions.
---@field toggle_unresolved boolean Whether to toggle unresolved discussions.
---@field keep_current_open boolean Whether to keep the current discussion open even if it should otherwise be closed.

---This function expands/collapses all nodes and their children according to the opts.
---@param tree NuiTree
---@param winid integer
---@param unlinked boolean
---@param opts ToggleNodesOptions
M.toggle_nodes = function(winid, tree, unlinked, opts)
  local current_node = tree:get_node()
  if current_node == nil then
    return
  end
  local root_node = common.get_root_node(tree, current_node)
  for _, node in ipairs(tree:get_nodes()) do
    if opts.toggle_resolved then
      if
        (unlinked and state.unlinked_discussion_tree.resolved_expanded)
        or (not unlinked and state.discussion_tree.resolved_expanded)
      then
        M.collapse_recursively(tree, node, root_node, opts.keep_current_open, true)
      else
        M.expand_recursively(tree, node, true)
      end
    end
    if opts.toggle_unresolved then
      if
        (unlinked and state.unlinked_discussion_tree.unresolved_expanded)
        or (not unlinked and state.discussion_tree.unresolved_expanded)
      then
        M.collapse_recursively(tree, node, root_node, opts.keep_current_open, false)
      else
        M.expand_recursively(tree, node, false)
      end
    end
  end
  -- Reset states of resolved discussions after toggling
  if opts.toggle_resolved then
    if unlinked then
      state.unlinked_discussion_tree.resolved_expanded = not state.unlinked_discussion_tree.resolved_expanded
    else
      state.discussion_tree.resolved_expanded = not state.discussion_tree.resolved_expanded
    end
  end
  -- Reset states of unresolved discussions after toggling
  if opts.toggle_unresolved then
    if unlinked then
      state.unlinked_discussion_tree.unresolved_expanded = not state.unlinked_discussion_tree.unresolved_expanded
    else
      state.discussion_tree.unresolved_expanded = not state.discussion_tree.unresolved_expanded
    end
  end
  tree:render()
  M.restore_cursor_position(winid, tree, current_node, root_node)
end

-- Get current node for restoring cursor position
---@param tree NuiTree The inline discussion tree or the unlinked discussion tree
---@param last_node NuiTree.Node|nil The last active discussion tree node in case we are not in any of the discussion trees
M.get_node_at_cursor = function(tree, last_node)
  if tree == nil then
    return
  end
  if vim.api.nvim_get_current_win() == vim.fn.win_findbuf(tree.bufnr)[1] then
    return tree:get_node()
  else
    return last_node
  end
end

---Restore cursor position to the original node if possible
---@param winid integer Window number of the discussions split
---@param tree NuiTree The inline discussion tree or the unlinked discussion tree
---@param original_node NuiTree.Node|nil The last node with the cursor
---@param root_node NuiTree.Node|nil The root node of the last node with the cursor
M.restore_cursor_position = function(winid, tree, original_node, root_node)
  if original_node == nil or tree == nil then
    return
  end
  local _, line_number = tree:get_node("-" .. tostring(original_node.id))
  -- If current_node has been collapsed, try to get line number of root node instead
  if line_number == nil then
    root_node = root_node and root_node or common.get_root_node(tree, original_node)
    if root_node ~= nil then
      _, line_number = tree:get_node("-" .. tostring(root_node.id))
    end
  end
  if line_number ~= nil then
    if vim.api.nvim_win_is_valid(winid) then
      vim.api.nvim_win_set_cursor(winid, { line_number, 0 })
    end
  end
end

---This function expands a node and its children.
---@param tree NuiTree
---@param node NuiTree.Node
---@param is_resolved boolean If true, expand resolved discussions. If false, expand unresolved discussions.
M.expand_recursively = function(tree, node, is_resolved)
  if node == nil then
    return
  end
  if common.is_node_note(node) and common.get_root_node(tree, node).resolved == is_resolved then
    node:expand()
  end
  local children = node:get_child_ids()
  for _, child in ipairs(children) do
    M.expand_recursively(tree, tree:get_node(child), is_resolved)
  end
end

---This function collapses a node and its children.
---@param tree NuiTree
---@param node NuiTree.Node
---@param current_root_node NuiTree.Node The root node of the current node.
---@param keep_current_open boolean If true, the current node stays open, even if it should otherwise be collapsed.
---@param is_resolved boolean If true, collapse resolved discussions. If false, collapse unresolved discussions.
M.collapse_recursively = function(tree, node, current_root_node, keep_current_open, is_resolved)
  if node == nil then
    return
  end
  local root_node = common.get_root_node(tree, node)
  if common.is_node_note(node) and root_node.resolved == is_resolved then
    if keep_current_open and root_node == current_root_node then
      return
    end
    node:collapse()
  end
  local children = node:get_child_ids()
  for _, child in ipairs(children) do
    M.collapse_recursively(tree, tree:get_node(child), current_root_node, keep_current_open, is_resolved)
  end
end

---Expands a given node in a given tree by it's ID
---@param tree NuiTree
---@param id string
M.open_node_by_id = function(tree, id)
  local node = tree:get_node(id)
  if node then
    node:expand()
  end
end

-- This function (settings.keymaps.discussion_tree.toggle_node) expands/collapses the current node and its children
M.toggle_node = function(tree)
  local node = tree:get_node()
  if node == nil then
    return
  end

  -- Switch to the "note" node from "note_body" nodes to enable toggling discussions inside comments
  if node.type == "note_body" then
    node = tree:get_node(node:get_parent_id())
  end
  if node == nil then
    return
  end

  local children = node:get_child_ids()
  if node == nil then
    return
  end
  if node:is_expanded() then
    node:collapse()
    if common.is_node_note(node) then
      for _, child in ipairs(children) do
        tree:get_node(child):collapse()
      end
    end
  else
    if common.is_node_note(node) then
      for _, child in ipairs(children) do
        tree:get_node(child):expand()
      end
    end
    node:expand()
  end

  tree:render()
end

return M
