local u = require("gitlab.utils")
local reviewer = require("gitlab.reviewer")
local common = require("gitlab.indicators.common")
local state = require("gitlab.state")
local NuiTree = require("nui.tree")
local NuiLine = require("nui.line")
local M = {}

---Build note header from note
---@param note Note|DraftNote
---@return string
M.build_note_header = function(note)
  if note.note then
    local file = note.position and (note.position.old_path or note.position.new_path) and "" or ""
    return "@" .. state.USER.username .. " " .. file
  end
  return "@" .. note.author.username .. " " .. u.time_since(note.created_at)
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

  local resolve_symbol = ""
  if resolve_info ~= nil and resolve_info.resolvable then
    resolve_symbol = resolve_info.resolved and state.settings.discussion_tree.resolved
        or state.settings.discussion_tree.unresolved
  end

  local noteHeader = M.build_note_header(note) .. " " .. resolve_symbol

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
    id = note.id,
    file_name = (type(note.position) == "table" and note.position.new_path),
    new_line = (type(note.position) == "table" and note.position.new_line),
    old_line = (type(note.position) == "table" and note.position.old_line),
    url = state.INFO.web_url .. "#note_" .. note.id,
    type = "note",
  }, text_nodes)

  return note_node, text, text_nodes
end

M.switch_can_edit_bufs = function(bool, ...)
  local bufnrs = { ... }
  ---@param v integer
  for _, v in ipairs(bufnrs) do
    u.switch_can_edit_buf(v, bool)
    vim.api.nvim_set_option_value("filetype", "gitlab", { buf = v })
  end
end

---@class TitleArg
---@field bufnr integer
---@field title string
---@field data table

---@param title_args TitleArg[]
M.add_empty_titles = function(title_args)
  for _, v in ipairs(title_args) do
    M.switch_can_edit_bufs(true, v.bufnr)
    local ns_id = vim.api.nvim_create_namespace("GitlabNamespace")
    vim.cmd("highlight default TitleHighlight guifg=#787878")

    -- Set empty title if applicable
    if type(v.data) ~= "table" or #v.data == 0 then
      vim.api.nvim_buf_set_lines(v.bufnr, 0, 1, false, { v.title })
      local linnr = 1
      vim.api.nvim_buf_set_extmark(
        v.bufnr,
        ns_id,
        linnr - 1,
        0,
        { end_row = linnr - 1, end_col = string.len(v.title), hl_group = "TitleHighlight" }
      )
    end
  end
end

---@param tree NuiTree
M.get_url = function(tree)
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
  return url
end

---@param tree NuiTree
M.open_in_browser = function(tree)
  local url = M.get_url(tree)
  if url == nil then
    return
  end
  u.open_in_browser(url)
end

---@param tree NuiTree
M.copy_node_url = function(tree)
  local url = M.get_url(tree)
  if url == nil then
    return
  end
  u.notify("Copied '" .. url .. "' to clipboard", vim.log.levels.INFO)
  vim.fn.setreg("+", url)
end

-- For developers!
M.print_node = function(tree)
  local current_node = tree:get_node()
  vim.print(current_node)
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

-- This function (settings.discussion_tree.toggle_node) expands/collapses the current node and its children
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

---Takes a node and returns the line where the note is positioned in the new SHA. If
---the line is not in the new SHA, returns nil
---@param node any
---@return number|nil
local function get_new_line(node)
  ---@type GitlabLineRange|nil
  local range = node.range
  if range == nil then
    return node.new_line
  end

  local _, start_new_line = common.parse_line_code(range.start.line_code)
  return start_new_line
end

---Takes a node and returns the line where the note is positioned in the old SHA. If
---the line is not in the old SHA, returns nil
---@param node any
---@return number|nil
local function get_old_line(node)
  ---@type GitlabLineRange|nil
  local range = node.range
  if range == nil then
    return node.old_line
  end

  local start_old_line, _ = common.parse_line_code(range.start.line_code)
  return start_old_line
end

-- This function (settings.discussion_tree.jump_to_reviewer) will jump the cursor to the reviewer's location associated with the note. The implementation depends on the reviewer
M.jump_to_reviewer = function(tree, refresh_view)
  local node = tree:get_node()
  local root_node = M.get_root_node(tree, node)
  if root_node == nil then
    u.notify("Could not get discussion node", vim.log.levels.ERROR)
    return
  end
  if root_node.file_name == nil then
    u.notify("This comment was not left on a particular location", vim.log.levels.WARN)
    return
  end
  reviewer.jump(root_node.file_name, get_new_line(root_node), get_old_line(root_node))
  refresh_view()
end

-- This function (settings.discussion_tree.jump_to_file) will jump to the file changed in a new tab
M.jump_to_file = function(tree)
  local node = tree:get_node()
  local root_node = M.get_root_node(tree, node)
  if root_node == nil then
    u.notify("Could not get discussion node", vim.log.levels.ERROR)
    return
  end
  if root_node.file_name == nil then
    u.notify("This comment was not left on a particular location", vim.log.levels.WARN)
    return
  end
  vim.cmd.tabnew()
  local line_number = get_new_line(root_node) or get_old_line(root_node)
  if line_number == nil then
    line_number = 1
  end
  local bufnr = vim.fn.bufnr(root_node.file_name)
  if bufnr ~= -1 then
    vim.cmd("buffer " .. bufnr)
    vim.api.nvim_win_set_cursor(0, { line_number, 0 })
    return
  end

  -- If buffer is not already open, open it
  vim.cmd("edit " .. root_node.file_name)
  vim.api.nvim_win_set_cursor(0, { line_number, 0 })
end

---Restore cursor position to the original node if possible
M.restore_cursor_position = function(winid, tree, original_node, root_node)
  local _, line_number = tree:get_node("-" .. tostring(original_node.id))
  -- If current_node is has been collapsed, get line number of root node instead
  if line_number == nil and root_node then
    _, line_number = tree:get_node("-" .. tostring(root_node.id))
  end
  if line_number ~= nil then
    vim.api.nvim_win_set_cursor(winid, { line_number, 0 })
  end
end

---This function (settings.discussion_tree.expand_recursively) expands a node and its children.
---@param tree NuiTree
---@param node NuiTree.Node
---@param is_resolved boolean If true, expand resolved discussions. If false, expand unresolved discussions.
M.expand_recursively = function(tree, node, is_resolved)
  if node == nil then
    return
  end
  if M.is_node_note(node) and M.get_root_node(tree, node).resolved == is_resolved then
    node:expand()
  end
  local children = node:get_child_ids()
  for _, child in ipairs(children) do
    M.expand_recursively(tree, tree:get_node(child), is_resolved)
  end
end

---@class ToggleNodesOptions
---@field toggle_resolved boolean Whether to toggle resolved discussions.
---@field toggle_unresolved boolean Whether to toggle unresolved discussions.
---@field keep_current_open boolean Whether to keep the current discussion open even if it should otherwise be closed.

---This function (settings.discussion_tree.toggle_nodes) expands/collapses all nodes and their children according to the opts.
---@param tree NuiTree
---@param winid integer
---@param unlinked boolean
---@param opts ToggleNodesOptions
M.toggle_nodes = function(winid, tree, unlinked, opts)
  local current_node = tree:get_node()
  if current_node == nil then
    return
  end
  local root_node = M.get_root_node(tree, current_node)
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

---This function (settings.discussion_tree.collapse_recursively) collapses a node and its children.
---@param tree NuiTree
---@param node NuiTree.Node
---@param current_root_node NuiTree.Node The root node of the current node.
---@param keep_current_open boolean If true, the current node stays open, even if it should otherwise be collapsed.
---@param is_resolved boolean If true, collapse resolved discussions. If false, collapse unresolved discussions.
M.collapse_recursively = function(tree, node, current_root_node, keep_current_open, is_resolved)
  if node == nil then
    return
  end
  local root_node = M.get_root_node(tree, node)
  if M.is_node_note(node) and root_node.resolved == is_resolved then
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

M.create_node_list_by_file_name = function(node_list)
  -- Create all the folder and file name nodes.
  local discussion_by_file_name = M.create_disscussions_by_file_name(node_list)

  -- Flatten empty folders
  for _, node in ipairs(discussion_by_file_name) do
    flatten_nodes(node)
  end

  sort_nodes(discussion_by_file_name)

  return discussion_by_file_name
end

M.create_disscussions_by_file_name = function(node_list)
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

---Toggle comments tree type between "simple" and "by_file_name"
M.toggle_tree_type = function(callback)
  if state.settings.discussion_tree.tree_type == "simple" then
    state.settings.discussion_tree.tree_type = "by_file_name"
  else
    state.settings.discussion_tree.tree_type = "simple"
  end
  callback()
end


return M
