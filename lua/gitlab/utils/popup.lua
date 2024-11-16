local M = {}

--- Setup autocommands for the popup
--- @param popup NuiPopup
--- @param layout NuiLayout|nil
M.set_up_autocommands = function(popup, layout)
  -- Make the popup/layout resizable
  popup:on("VimResized", function()
    if layout ~= nil then
      layout:update()
    else
      popup:update_layout()
    end
  end)
end

return M
