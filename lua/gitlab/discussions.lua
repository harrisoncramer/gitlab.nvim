local u                   = require("gitlab.utils")
local NuiTree             = require("nui.tree")
local NuiSplit            = require("nui.split")
local job                 = require("gitlab.job")
local state               = require("gitlab.state")
local Popup               = require("nui.popup")
local settings            = require("gitlab.settings")

local M                   = {}

-- Places all of the discussions into a readable tree
-- in a split window
M.split                   = nil
M.split_visible           = false
M.list_discussions        = function()
  job.run_job("discussions", "GET", nil, function(data)
    if type(data.discussions) ~= "table" then
      vim.notify("No discussions for this MR", vim.log.levels.WARN)
      return
    end

    local split = NuiSplit({
      buf_options = { modifiable = false },
      relative = state.settings.discussion_tree.relative,
      position = state.settings.discussion_tree.position,
      size = state.settings.discussion_tree.size,
    })
    split:mount()

    M.split = split
    M.split_visible = true

    local buf = split.bufnr
    state.SPLIT_BUF = buf

    local tree_nodes = M.add_discussions_to_table(data.discussions)

    state.tree = NuiTree({ nodes = tree_nodes, bufnr = buf })
    M.set_tree_keymaps(buf)

    state.tree:render()
    vim.api.nvim_buf_set_option(buf, 'filetype', 'markdown')
    u.darken_metadata(buf, '')
  end)
end

-- The reply popup will mount in a window when you trigger it (settings.discussion_tree.reply_to_comment) when hovering over a node in the discussion tree.
local replyPopup          = Popup(u.create_popup_state("Reply", "80%", "80%"))
M.reply                   = function(discussion_id)
  replyPopup:mount()
  settings.set_popup_keymaps(replyPopup, M.send_reply(discussion_id))
end

-- This function will send the reply to the Go API
M.send_reply              = function(discussion_id)
  return function(text)
    local jsonTable = { discussion_id = discussion_id, reply = text }
    local json = vim.json.encode(jsonTable)
    job.run_job("reply", "POST", json, function(data)
      M.add_note_to_tree(data.note, discussion_id)
    end)
  end
end

-- This function (settings.discussion_tree.jump_to_location) will
-- jump you to the file and line where the comment was left
M.jump_to_file            = function()
  local node = state.tree:get_node()
  if node == nil then return end

  local wins = vim.api.nvim_list_wins()
  local discussion_win = vim.api.nvim_get_current_win()
  for _, winId in ipairs(wins) do
    if winId ~= discussion_win then
      vim.api.nvim_set_current_win(winId)
    end
  end

  local discussion_node = M.get_root_node(node)
  local review_buffer_range = M.get_review_buffer_range(discussion_node)
  if review_buffer_range == nil then return end

  if review_buffer_range == nil then return end
  local lines = {}
  for i = review_buffer_range[1], review_buffer_range[2], 1 do
    local line_content = vim.api.nvim_buf_get_lines(state.REVIEW_BUF, i - 1, i, false)[1]
    if string.find(line_content, "⋮") then
      table.insert(lines, { line_content = line_content, line_number = i })
    end
  end

  -- Extract line numbers from each line
  for _, line in ipairs(lines) do
    local data, _ = line.line_content:match("(.-)" .. "│" .. "(.*)")
    local line_data = {}
    if data ~= nil then
      local old_line = u.trim(u.get_first_chunk(data, "[^" .. "⋮" .. "]+"))
      local new_line = u.trim(u.get_last_chunk(data, "[^" .. "⋮" .. "]+"))
      line_data.new_line = tonumber(new_line)
      line_data.old_line = tonumber(old_line)
    end

    if node.old_line == line_data.old_line and node.new_line == line_data.new_line then
      vim.api.nvim_win_set_cursor(0, { line.line_number, 0 })
      vim.api.nvim_set_current_buf(state.REVIEW_BUF)
    end
  end
end

M.get_review_buffer_range = function(node)
  local lines = vim.api.nvim_buf_get_lines(state.REVIEW_BUF, 0, -1, false)
  local start = nil
  local stop = nil

  for i, line in ipairs(lines) do
    if start ~= nil and stop ~= nil then return { start, stop } end
    if M.starts_with_file_symbol(line) then
      -- Check if the file name matches the node name
      local file_name = u.get_last_chunk(line)
      if file_name == node.file_name then
        start = i
      elseif start ~= nil then
        stop = i
      end
    end
  end

  -- We've reached the end of the file, set "stop" in case we already found start
  stop = #lines
  if start ~= nil and stop ~= nil then return { start, stop } end
end

-- TODO: Check end of file too
M.starts_with_file_symbol = function(line)
  for _, substring in ipairs({
    state.settings.review_pane.added_file,
    state.settings.review_pane.removed_file,
    state.settings.review_pane.modified_file,
    "[Process exited 0]"
  }) do
    if string.sub(line, 1, string.len(substring)) == substring then
      return true
    end
  end
  return false
end


M.set_tree_keymaps         = function(buf)
  vim.keymap.set('n', state.settings.discussion_tree.jump_to_location, function()
    M.jump_to_file()
  end, { buffer = true })

  vim.keymap.set('n', state.settings.discussion_tree.edit_comment, function()
    require("gitlab.comment").edit_comment()
  end, { buffer = true })

  vim.keymap.set('n', state.settings.discussion_tree.delete_comment, function()
    require("gitlab.comment").delete_comment()
  end, { buffer = true })

  vim.keymap.set('n', state.settings.discussion_tree.toggle_resolved, function()
    require("gitlab.comment").toggle_resolved()
  end, { buffer = true })

  -- Expands/collapses the current node
  vim.keymap.set('n', state.settings.discussion_tree.toggle_node, function()
      local node = state.tree:get_node()
      if node == nil then return end
      local children = node:get_child_ids()
      if node == nil then return end
      if node:is_expanded() then
        node:collapse()
        for _, child in ipairs(children) do
          state.tree:get_node(child):collapse()
        end
      else
        for _, child in ipairs(children) do
          state.tree:get_node(child):expand()
        end
        node:expand()
      end

      state.tree:render()
      u.darken_metadata(buf, '')
    end,
    { buffer = true })

  vim.keymap.set('n', 'r', function()
    local node = state.tree:get_node()
    if node == nil then return end
    local discussion_node = M.get_root_node(node)
    M.reply(tostring(discussion_node.id))
  end, { buffer = true })
end

--
-- 🌲 Helper Functions
--

M.get_root_node            = function(node)
  if (not node.is_root) then
    local parent_id = node:get_parent_id()
    return M.get_root_node(state.tree:get_node(parent_id))
  else
    return node
  end
end

M.get_note_node            = function(node)
  if (not node.is_note) then
    local parent_id = node:get_parent_id()
    if parent_id == nil then return node end
    return M.get_note_node(state.tree:get_node(parent_id))
  else
    return node
  end
end

M.build_note_body          = function(note, resolve_info)
  local text_nodes = {}
  for bodyLine in note.body:gmatch("[^\n]+") do
    local line = u.attach_uuid(bodyLine)
    table.insert(text_nodes, NuiTree.Node({
      new_line = note.position.new_line,
      old_line = note.position.old_line,
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

M.build_note               = function(note, resolve_info)
  local text, text_nodes = M.build_note_body(note, resolve_info)
  local note_node = NuiTree.Node({
    text = text,
    id = note.id,
    file_name = note.position.new_path,
    new_line = note.position.new_line,
    old_line = note.position.old_line,
    is_note = true,
  }, text_nodes)

  return note_node, text, text_nodes
end

M.add_note_to_tree         = function(note, discussion_id)
  local note_node = M.build_note(note)
  note_node:expand()
  state.tree:add_node(note_node, discussion_id and ("-" .. discussion_id) or nil)
  state.tree:render()
  local buf = vim.api.nvim_get_current_buf()
  u.darken_metadata(buf, '')
  vim.notify("Sent reply!", vim.log.levels.INFO)
end

M.refresh_tree             = function()
  job.run_job("discussions", "GET", nil, function(data)
    if type(data.discussions) ~= "table" then
      vim.notify("No discussions for this MR")
      return
    end

    if not state.SPLIT_BUF or (vim.fn.bufwinid(state.SPLIT_BUF) == -1) then return end

    vim.api.nvim_buf_set_option(state.SPLIT_BUF, 'modifiable', true)
    vim.api.nvim_buf_set_option(state.SPLIT_BUF, 'readonly', false)
    vim.api.nvim_buf_set_lines(state.SPLIT_BUF, 0, -1, false, {})
    vim.api.nvim_buf_set_option(state.SPLIT_BUF, 'readonly', true)
    vim.api.nvim_buf_set_option(state.SPLIT_BUF, 'modifiable', false)

    local tree_nodes = M.add_discussions_to_table(data.discussions)
    state.tree = NuiTree({ nodes = tree_nodes, bufnr = state.SPLIT_BUF })
    M.set_tree_keymaps(state.SPLIT_BUF)
    state.tree:render()
    vim.api.nvim_buf_set_option(state.SPLIT_BUF, 'filetype', 'markdown')
    u.darken_metadata(state.SPLIT_BUF, '')
  end)
end

M.add_discussions_to_table = function(discussions)
  local t = {}
  for _, discussion in ipairs(discussions) do
    local discussion_children = {}

    -- These properties are filled in by the first note
    local root_text = ''
    local root_note_id = ''
    local root_line_number = 0
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
        root_file_name = note.position.new_path
        root_new_line = note.position.new_line
        root_old_line = note.position.old_line
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

return M
