local M = {}
local u = require("gitlab.utils")
local popup = require("gitlab.popup")
local event = require("nui.utils.autocmd").event
local state = require("gitlab.state")
local List = require("gitlab.utils.list")
local Popup = require("nui.popup")

M.open = function()
  local bufnr = vim.api.nvim_get_current_buf()
  local keymaps = vim.api.nvim_buf_get_keymap(bufnr, "n")
  local help_content_lines = List.new(keymaps):reduce(function(agg, keymap)
    if keymap.desc ~= nil then
      local new_line = string.format("%s: %s", keymap.lhs:gsub(" ", "<space>"), keymap.desc)
      table.insert(agg, new_line)
    end
    return agg
  end, {})

  table.insert(help_content_lines, "")
  table.insert(
    help_content_lines,
    string.format(
      "%s = draft; %s = unlinked comment; %s = resolved",
      state.settings.discussion_tree.draft,
      state.settings.discussion_tree.unlinked,
      state.settings.discussion_tree.resolved
    )
  )

  local longest_line = u.get_longest_string(help_content_lines)
  local opts = { "Help", state.settings.popup.help, longest_line + 3, #help_content_lines, 70 }
  local help_popup = Popup(popup.create_popup_state(unpack(opts)))

  help_popup:on(event.BufLeave, function()
    help_popup:unmount()
  end)

  popup.set_up_autocommands(help_popup, nil, vim.api.nvim_get_current_win(), opts)

  help_popup:mount()

  popup.set_popup_keymaps(help_popup, "Help", nil)
  local currentBuffer = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(currentBuffer, 0, #help_content_lines, false, help_content_lines)
  u.switch_can_edit_buf(currentBuffer, false)
end

return M
