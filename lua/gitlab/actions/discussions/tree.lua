local state = require("gitlab.state")
local u = require("gitlab.utils")
local NuiTree = require("nui.tree")

local M = {}

local attach_uuid = function(str)
  return { text = str, id = u.uuid() }
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

---Build note header from note.
---@param note Note
---@return string
local function build_note_header(note)
  return "@" .. note.author.username .. " " .. u.time_since(note.created_at)
end

---Build note node body
---@param note Note
---@param resolve_info table?
---@return string
---@return NuiTree.Node[]
local function build_note_body(note, resolve_info)
  local text_nodes = {}
  for bodyLine in note.body:gmatch("[^\n]+") do
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

  local noteHeader = build_note_header(note) .. " " .. resolve_symbol

  return noteHeader, text_nodes
end

---Build note node
---@param note Note
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

---Create nodes for NuiTree from discussions
---@param items Discussion[]
---@param unlinked boolean? False or nil means that discussions are linked to code lines
---@return NuiTree.Node[]
M.add_discussions_to_table = function(items, unlinked)
  local t = {}
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
    local resolved = false
    local undefined_type = false
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

        -- This appears to be a Gitlab 🐛 where the "type" is returned as an empty string in some cases
        -- We link these comments to the old file by default
        if
          type(note.position) == "table"
          and note.position.line_range ~= nil
          and note.position.line_range.start.type == ""
        then
          undefined_type = true
        end
      else -- Otherwise insert it as a child node...
        local note_node = M.build_note(note)
        table.insert(discussion_children, note_node)
      end
    end

    -- Creates the first node in the discussion, and attaches children
    local body = u.spread(root_text_nodes, discussion_children)
    local root_node = NuiTree.Node({
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
      undefined_type = undefined_type,
      url = root_url,
    }, body)

    table.insert(t, root_node)
  end
  if state.settings.discussion_tree.tree_type == "simple" or unlinked == true then
    return t
  end

  -- Create all the folder and file name nodes.
  local discussion_by_file_name = {}
  local top_level_path_to_node = {}
  for _, node in ipairs(t) do
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

  -- Flatten empty folders
  for _, node in ipairs(discussion_by_file_name) do
    flatten_nodes(node)
  end
  sort_nodes(discussion_by_file_name)

  return discussion_by_file_name
end

return M
