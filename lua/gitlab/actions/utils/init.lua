local u = require("gitlab.utils")
local state = require("gitlab.state")
local NuiTree = require("nui.tree")
local NuiLine = require("nui.line")
local M = {}

---Build note header from note
---@param note Note|DraftNote
---@return string
M.build_note_header = function(note)
  if note.note then
    return "@" .. state.USER.username
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

return M
