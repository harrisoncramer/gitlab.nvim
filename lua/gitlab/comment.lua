local Menu               = require("nui.menu")
local NuiTree            = require("nui.tree")
local notify             = require("notify")
local Job                = require("plenary.job")
local state              = require("gitlab.state")
local u                  = require("gitlab.utils")
local keymaps            = require("gitlab.keymaps")
local Popup              = require("nui.popup")
local M                  = {}

local commentPopup       = Popup(u.create_popup_state("Comment", "40%", "60%"))
local editPopup          = Popup(u.create_popup_state("Edit Comment", "80%", "80%"))

M.line_status            = nil

M.create_comment         = function()
  if u.base_invalid() then return end
  commentPopup:mount()
  keymaps.set_popup_keymaps(commentPopup, M.confirm_create_comment)
end

-- Sends the comment to Gitlab
M.confirm_create_comment = function(text)
  if u.base_invalid() then return end
  local relative_file_path = u.get_relative_file_path()
  local current_line_number = u.get_current_line_number()
  Job:new({
    command = state.BIN,
    args = {
      "comment",
      state.PROJECT_ID,
      current_line_number,
      relative_file_path,
      text,
    },
    -- TODO: Render the tree after comment creation. Refresh?
    on_stdout = u.print_success,
    on_stderr = u.print_error
  }):start()
end

M.delete_comment         = function()
  local menu = Menu({
    position = "50%",
    size = {
      width = 25,
    },
    border = {
      style = "single",
      text = {
        top = "Delete Comment?",
        top_align = "center",
      },
    },
    win_options = {
      winhighlight = "Normal:Normal,FloatBorder:Normal",
    },
  }, {
    lines = {
      Menu.item("Confirm"),
      Menu.item("Cancel"),
    },
    max_width = 20,
    keymap = {
      focus_next = state.keymaps.dialogue.focus_next,
      focus_prev = state.keymaps.dialogue.focus_prev,
      close = state.keymaps.dialogue.close,
      submit = state.keymaps.dialogue.submit,
    },
    on_submit = function(item)
      if item.text == "Confirm" then
        local note_id
        local node = state.tree:get_node()
        if node.is_note then
          note_id = node:get_id()
        end
        local parentId = node:get_parent_id()
        while (parentId ~= nil) do
          node = state.tree:get_node(parentId)
          parentId = node:get_parent_id()
          if node.is_note then
            note_id = node:get_id()
          end
        end
        local discussion_id = node:get_id()
        discussion_id = string.sub(discussion_id, 2) -- Remove the "-" at the start
        note_id = string.sub(note_id, 2)             -- Remove the "-" at the start
        Job:new({
          command = state.BIN,
          args = {
            "deleteComment",
            state.PROJECT_ID,
            discussion_id,
            note_id,
          },
          on_stdout = function(_, line)
            vim.schedule(function()
              if line ~= nil and line ~= "" then
                notify(line, "info")
                state.tree:remove_node("-" .. note_id)
                local discussion_node = state.tree:get_node("-" .. discussion_id)
                if not discussion_node:has_children() then
                  state.tree:remove_node("-" .. discussion_id)
                end
                state.tree:render()
              end
            end)
          end,
          on_stderr = u.print_error
        }):start()
      end
    end,
  })
  menu:mount()
end


M.edit_comment = function()
  if u.base_invalid() then return end
  local node = state.tree:get_node()
  if node.is_discussion then return end
  if node.is_body then
    local parentId = node:get_parent_id()
    node = state.tree:get_node(parentId) -- Get the node for the comment
  end

  editPopup:mount()

  local note_id = string.sub(node:get_id(), 2) -- Remove the "-" at the start
  local discussion_id = node:get_parent_id()
  discussion_id = string.sub(discussion_id, 2) -- Remove the "-" at the start

  state.ACTIVE_DISCUSSION = discussion_id
  state.ACTIVE_NOTE = note_id

  local lines = {}
  local childrenIds = node:get_child_ids()
  for _, value in ipairs(childrenIds) do
    local line = state.tree:get_node(value).text
    table.insert(lines, line)
  end

  local currentBuffer = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(currentBuffer, 0, -1, false, lines)
  keymaps.set_popup_keymaps(editPopup, M.send_edits)
end

M.send_edits   = function(text)
  Job:new({
    command = state.BIN,
    args = {
      "editComment",
      state.PROJECT_ID,
      state.ACTIVE_DISCUSSION,
      state.ACTIVE_NOTE,
      text,
    },
    on_stdout = function(_, line)
      local note = vim.json.decode(line)
      if note == nil then
        notify("There was an issue editing the note", "error")
        return
      end

      vim.schedule(function()
        local node = state.tree:get_node("-" .. state.ACTIVE_NOTE)

        local childrenIds = node:get_child_ids()
        for _, value in ipairs(childrenIds) do
          state.tree:remove_node(value)
        end

        local newNoteTextNodes = {}
        for bodyLine in note.body:gmatch("[^\n]+") do
          table.insert(newNoteTextNodes, NuiTree.Node({ text = bodyLine, is_body = true }, {}))
        end

        state.tree:set_nodes(newNoteTextNodes, "-" .. state.ACTIVE_NOTE)

        state.tree:render()
        local buf = vim.api.nvim_get_current_buf()
        u.darken_metadata(buf, '')
        notify("Edited comment!")
      end)
    end,
    on_stderr = u.print_error
  }):start()
end

return M
