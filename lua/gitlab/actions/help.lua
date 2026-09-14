local u = require("gitlab.utils")
local popup = require("gitlab.popup")
local event = require("nui.utils.autocmd").event
local state = require("gitlab.state")
local List = require("gitlab.utils.list")
local Popup = require("nui.popup")

local M = {}

---@class HelpPopupOpts
---@field discussion_tree? boolean Whether help popup is for the discussion tree

---Open the help popup.
---@param opts? HelpPopupOpts Table with options for the help popup
M.open = function(opts)
  local help_opts = opts or {}
  local bufnr = vim.api.nvim_get_current_buf()
  local keymaps = vim.api.nvim_buf_get_keymap(bufnr, "n")
  local help_content_lines = List.new(keymaps):reduce(function(agg, keymap)
    if keymap.desc ~= nil then
      local new_line = string.format("%s: %s", keymap.lhs:gsub(" ", "<space>"), keymap.desc)
      table.insert(agg, new_line)
    end
    return agg
  end, {})

  if help_opts.discussion_tree then
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
  end

  local max_line_length = u.get_max_length(help_content_lines)
  ---@type PopupOpts
  local popup_opts = {
    title = "Help",
    user_settings = state.settings.popup.help,
    width = max_line_length + 3,
    height = #help_content_lines,
    zindex = 70,
  }
  local help_popup = Popup(popup.create_popup_state(popup_opts))

  help_popup:on(event.BufLeave, function()
    help_popup:unmount()
  end)

  popup.set_up_autocommands(help_popup, nil, vim.api.nvim_get_current_win(), popup_opts)

  help_popup:mount()

  popup.set_popup_keymaps(help_popup, "Help", nil)
  local currentBuffer = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(currentBuffer, 0, #help_content_lines, false, help_content_lines)
  u.switch_can_edit_buf(currentBuffer, false)
end

return M
