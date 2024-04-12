local u = require("gitlab.utils")
local au = require("gitlab.actions.utils")
local state = require("gitlab.state")
local NuiTree = require("nui.tree")
local M = {}

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

  local noteHeader = au.build_note_header(note) .. " " .. resolve_symbol

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

return M
