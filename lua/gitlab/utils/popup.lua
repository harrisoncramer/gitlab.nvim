local u = require("gitlab.utils")

local M = {}

--- Setup autocommands for the popup
--- @param popup NuiPopup
--- @param layout NuiLayout|nil
--- @param opts table|nil Table with options for updating the popup
M.set_up_autocommands = function(popup, layout, opts)
  -- Make the popup/layout resizable
  popup:on("VimResized", function()
    if layout ~= nil then
      layout:update()
    else
      popup:update_layout(opts and u.create_popup_state(unpack(opts)))
    end
  end)
end

return M
