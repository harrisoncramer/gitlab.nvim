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

M.editable_popup_opts = {
  action_before_close = true,
  action_before_exit = false,
  save_to_temp_register = true,
}

M.non_editable_popup_opts = {
  action_before_close = true,
  action_before_exit = false,
  save_to_temp_register = false,
}

-- Get the index of the next popup when cycling forward
local function next_index(i, n, count)
  count = count > 0 and count or 1
  for _ = 1, count do
    if i < n then
      i = i + 1
    elseif i == n then
      i = 1
    end
  end
  return i
end

---Get the index of the previous popup when cycling backward
---@param i integer The current index
---@param n integer The total number of popups
---@param count integer The count used with the keymap (replaced with 1 if no count was given)
local function prev_index(i, n, count)
  count = count > 0 and count or 1
  for _ = 1, count do
    if i > 1 then
      i = i - 1
    elseif i == 1 then
      i = n
    end
  end
  return i
end

---Setup keymaps for cycling popups. The keymap accepts count.
---@param popups table Table of Popups
M.set_cycle_popups_keymaps = function(popups)
  local keymaps = require("gitlab.state").settings.keymaps
  if keymaps.disable_all or keymaps.popup.disable_all then
    return
  end

  local number_of_popups = #popups
  for i, popup in ipairs(popups) do
    if keymaps.popup.next_field then
      popup:map("n", keymaps.popup.next_field, function()
        vim.api.nvim_set_current_win(popups[next_index(i, number_of_popups, vim.v.count)].winid)
      end, { desc = "Go to next field (accepts count)", nowait = keymaps.popup.next_field_nowait })
    end
    if keymaps.popup.prev_field then
      popup:map("n", keymaps.popup.prev_field, function()
        vim.api.nvim_set_current_win(popups[prev_index(i, number_of_popups, vim.v.count)].winid)
      end, { desc = "Go to previous field (accepts count)", nowait = keymaps.popup.prev_field_nowait })
    end
  end
end

return M
