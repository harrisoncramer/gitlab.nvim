local u            = require("gitlab.utils")
local NuiTree      = require("nui.tree")
local notify       = require("notify")
local state        = require("gitlab.state")
local Job          = require("plenary.job")
local Popup        = require("nui.popup")
local keymaps      = require("gitlab.keymaps")

local M            = {}

local replyPopup   = Popup(u.create_popup_state("Reply", "80%", "80%"))

M.reply            = function()
  if u.base_invalid() then return end
  replyPopup:mount()
  keymaps.set_popup_keymaps(replyPopup, M.send_reply)
end

M.send_reply       = function(text)
  Job:new({
    command = state.BIN,
    args = {
      "reply",
      state.PROJECT_ID,
      state.ACTIVE_DISCUSSION,
      text,
    },
    on_stdout = function(_, line)
      local note = vim.json.decode(line)
      if note == nil then
        notify("There was an issue creating the note", "error")
        return
      end

      local note_node = M.build_note(note)
      note_node:expand()

      state.tree:add_node(note_node, "-" .. state.ACTIVE_DISCUSSION)
      vim.schedule(function()
        state.tree:render()
        local buf = vim.api.nvim_get_current_buf()
        u.darken_metadata(buf, '')
        notify("Sent reply!")
      end)
    end,
    on_stderr = u.print_error
  }):start()
end

-- Places all of the discussions into a readable list
M.list_discussions = function()
  if u.base_invalid() then return end
  Job:new({
    command = state.BIN,
    args = { "listDiscussions", state.PROJECT_ID },
    on_stdout = function(_, line)
      local discussions = vim.json.decode(line)
      M.discussions = discussions
      vim.schedule(function()
        vim.cmd.tabnew()
        local buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_command("vsplit")
        vim.api.nvim_buf_set_option(buf, 'filetype', 'markdown')
        vim.api.nvim_set_current_buf(buf)
        if discussions == nil then
          notify("No discussions found for this MR", "warn")
        else
          local allDiscussions = {}
          for i, discussion in ipairs(discussions) do
            local discussionChildren = {}
            for _, note in ipairs(discussion.notes) do
              local note_node = M.build_note(note)
              if i == 1 then
                note_node:expand()
              end
              table.insert(discussionChildren, note_node)
            end
            local discussionNode = NuiTree.Node({
                text = discussion.id,
                id = discussion.id,
                is_discussion = true
              },
              discussionChildren)
            if i == 1 then
              discussionNode:expand()
            end
            table.insert(allDiscussions, discussionNode)
          end
          state.tree = NuiTree({ nodes = allDiscussions, bufnr = buf })

          M.set_tree_keymaps(buf)

          state.tree:render()
          vim.api.nvim_buf_set_option(buf, 'filetype', 'markdown')
          u.darken_metadata(buf, '')
          if not is_refresh then
            M.jump_to_file()
          end
        end
      end)
    end,
    on_stderr = u.print_error,
  }):start()
end

M.jump_to_file     = function()
  local node = state.tree:get_node()
  if node == nil then return end

  local childrenIds = node:get_child_ids()
  -- We have selected a note node
  if node.file_name ~= nil then
    u.jump_to_file(node.file_name, node.line_number)
  elseif node.is_body then
    local parentId = node:get_parent_id()
    local parent = state.tree:get_node(parentId)
    if parent == nil then return end
    u.jump_to_file(parent.file_name, parent.line_number)
  else
    local firstChild = state.tree:get_node(childrenIds[1])
    if firstChild == nil then return end
    u.jump_to_file(firstChild.file_name, firstChild.line_number)
  end
end

M.set_tree_keymaps = function(buf)
  -- Jump to file location where comment was left
  vim.keymap.set('n', state.keymaps.discussion_tree.jump_to_location, function()
    M.jump_to_file()
  end, { buffer = true })

  vim.keymap.set('n', state.keymaps.discussion_tree.edit_comment, function()
    require("gitlab.comment").edit_comment()
  end, { buffer = true })

  vim.keymap.set('n', state.keymaps.discussion_tree.delete_comment, function()
    require("gitlab.comment").delete_comment()
  end)

  -- Expand/collapse the current node
  vim.keymap.set('n', state.keymaps.discussion_tree.toggle_node, function()
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

    -- Get closest discussion parent
    if node.is_body then
      local parentId = node:get_parent_id()
      local parent = state.tree:get_node(parentId)
      if parent == nil then return end
      parentId = parent:get_parent_id()
      parent = state.tree:get_node(parentId)
      if parent == nil then return end
      node = parent
    elseif node.is_note then
      local parentId = node:get_parent_id()
      local parent = state.tree:get_node(parentId)
      if parent == nil then return end
      node = parent
    end

    state.ACTIVE_DISCUSSION = node.id
    M.reply()
  end, { buffer = true })
end

M.build_note       = function(note)
  local noteTextNodes = {}
  for bodyLine in note.body:gmatch("[^\n]+") do
    table.insert(noteTextNodes, NuiTree.Node({ text = bodyLine, is_body = true }, {}))
  end
  local noteHeader = "@" ..
      note.author.username .. " on " .. u.format_date(note.created_at)
  local note_node = NuiTree.Node(
    {
      text = noteHeader,
      id = note.id,
      file_name = note.position.new_path,
      line_number = note.position.new_line,
      is_note = true
    }, noteTextNodes)

  return note_node
end

return M
