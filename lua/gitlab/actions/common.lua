-- This module contains code shared between at least two modules. This includes
-- actions common to multiple tree types, as well as general utility functions
-- that are specific to actions (like jumping to a file or opening a URL)
local List = require("gitlab.utils.list")
local u = require("gitlab.utils")
local reviewer = require("gitlab.reviewer")
local common_indicators = require("gitlab.indicators.common")
local state = require("gitlab.state")
local M = {}

---Build note header from note
---@param note Note|DraftNote
---@return string
M.build_note_header = function(note)
  if note.note then
    return "@" .. state.USER.username .. " " .. ""
  end
  return "@" .. note.author.username .. " " .. u.time_since(note.created_at)
end

M.switch_can_edit_bufs = function(bool, ...)
  local bufnrs = { ... }
  ---@param v integer
  for _, v in ipairs(bufnrs) do
    u.switch_can_edit_buf(v, bool)
    vim.api.nvim_set_option_value("filetype", "gitlab", { buf = v })
  end
end

---Takes in a chunk of text separated by new line characters and returns a lua table
---@param content string
---@return table
M.build_content = function(content)
  local description_lines = {}
  for line in u.split_by_new_lines(content) do
    table.insert(description_lines, line)
  end
  table.insert(description_lines, "")
  return description_lines
end

M.add_empty_titles = function()
  local draft_notes = require("gitlab.actions.draft_notes")
  local discussions = require("gitlab.actions.discussions")
  local linked, unlinked, drafts =
    List.new(u.ensure_table(state.DISCUSSION_DATA and state.DISCUSSION_DATA.discussions)),
    List.new(u.ensure_table(state.DISCUSSION_DATA and state.DISCUSSION_DATA.unlinked_discussions)),
    List.new(u.ensure_table(state.DRAFT_NOTES))

  local position_drafts = drafts:filter(function(note)
    return draft_notes.has_position(note)
  end)
  local non_positioned_drafts = drafts:filter(function(note)
    return not draft_notes.has_position(note)
  end)

  local fields = {
    {
      bufnr = discussions.linked_bufnr,
      count = #linked + #position_drafts,
      title = "No Discussions for this MR",
    },
    {
      bufnr = discussions.unlinked_bufnr,
      count = #unlinked + #non_positioned_drafts,
      title = "No Notes (Unlinked Discussions) for this MR",
    },
  }

  for _, v in ipairs(fields) do
    if v.bufnr ~= nil then
      M.switch_can_edit_bufs(true, v.bufnr)
      local ns_id = vim.api.nvim_create_namespace("GitlabNamespace")
      vim.cmd("highlight default TitleHighlight guifg=#787878")

      -- Set empty title if applicable
      if v.count == 0 then
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
  if url ~= nil then
    u.open_in_browser(url)
  end
end

---@param tree NuiTree
M.copy_node_url = function(tree)
  local url = M.get_url(tree)
  if url == nil then
    vim.fn.setreg("+", url)
    u.notify("Copied '" .. url .. "' to clipboard", vim.log.levels.INFO)
  end
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

  local _, start_new_line = common_indicators.parse_line_code(range.start.line_code)
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

  local start_old_line, _ = common_indicators.parse_line_code(range.start.line_code)
  return start_old_line
end

-- This function (settings.discussion_tree.jump_to_reviewer) will jump the cursor to the reviewer's location associated with the note. The implementation depends on the reviewer
M.jump_to_reviewer = function(tree, callback)
  local node = tree:get_node()
  local root_node = M.get_root_node(tree, node)
  if root_node == nil then
    u.notify("Could not get discussion node", vim.log.levels.ERROR)
    return
  end
  local line_number = (root_node.new_line or root_node.old_line or 1)
  if root_node.range then
    local start_old_line, start_new_line = common_indicators.parse_line_code(root_node.range.start.line_code)
    line_number = root_node.old_line and start_old_line or start_new_line
  end
  reviewer.jump(root_node.file_name, line_number, root_node.old_line == nil)
  callback()
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

return M
