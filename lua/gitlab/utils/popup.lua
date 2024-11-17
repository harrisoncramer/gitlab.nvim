local u = require("gitlab.utils")

local M = {}

--- Setup autocommands for the popup
--- @param popup NuiPopup
--- @param layout NuiLayout|nil
--- @param previous_window number|nil Number of window active before the popup was opened
--- @param opts table|nil Table with options for updating the popup
M.set_up_autocommands = function(popup, layout, previous_window, opts)
  -- Make the popup/layout resizable
  popup:on("VimResized", function()
    if layout ~= nil then
      layout:update()
    else
      popup:update_layout(opts and u.create_popup_state(unpack(opts)))
    end
  end)

  -- After closing the popup, refocus the previously active window
  if previous_window ~= nil then
    popup:on("BufHidden", function()
      vim.schedule(function()
        vim.api.nvim_set_current_win(previous_window)
      end)
    end)
  end
end

return M
