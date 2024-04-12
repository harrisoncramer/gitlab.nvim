local state = require("gitlab.state")
local trees = require("gitlab.actions.trees")
local u = require("gitlab.utils")
local au = require("gitlab.actions.utils")
local NuiTree = require("nui.tree")

local M = {}

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
    ---@type GitlabLineRange|nil
    local range = nil
    local resolved = false
    local root_new_line = nil
    local root_old_line = nil
    local root_url

    for j, note in ipairs(discussion.notes) do
      if j == 1 then
        _, root_text, root_text_nodes = trees.build_note(note, { resolved = note.resolved, resolvable = note.resolvable })
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
        local note_node = trees.build_note(note)
        table.insert(discussion_children, note_node)
      end
    end

    -- Creates the first node in the discussion, and attaches children
    local body = u.spread(root_text_nodes, discussion_children)
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

  return au.create_node_list_by_file_name(t)
end


return M
