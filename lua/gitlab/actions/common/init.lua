local u = require("gitlab.utils")
local reviewer = require("gitlab.reviewer")
local common = require("gitlab.indicators.common")
local state = require("gitlab.state")
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

return M
