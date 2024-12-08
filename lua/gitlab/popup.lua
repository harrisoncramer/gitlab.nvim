local u = require("gitlab.utils")

local M = {}

---Get the popup view_opts
---@param title string The string to appear on top of the popup
---@param user_settings table|nil User-defined popup settings
---@param width number? Override default width
---@param height number? Override default height
---@param zindex number? Override default zindex
---@return table
M.create_popup_state = function(title, user_settings, width, height, zindex)
  local settings = u.merge(require("gitlab.state").settings.popup, user_settings or {})
  local view_opts = {
    buf_options = {
      filetype = "markdown",
    },
    relative = "editor",
    enter = true,
    focusable = true,
    zindex = zindex or 50,
    border = {
      style = settings.border,
      text = {
        top = title,
      },
    },
    position = settings.position,
    size = {
      width = width and math.min(width, vim.o.columns - 2) or settings.width,
      height = height and math.min(height, vim.o.lines - 3) or settings.height,
    },
    opacity = settings.opacity,
  }

  return view_opts
end

---Create view_opts for Box popups used inside popup Layouts
---@param title string|nil The string to appear on top of the popup
---@param enter boolean Whether the pop should be focused after creation
---@param settings table User defined popup settings
---@return table
M.create_box_popup_state = function(title, enter, settings)
  return {
    buf_options = {
      filetype = "markdown",
    },
    enter = enter or false,
    focusable = true,
    border = {
      style = settings.border,
      text = {
        top = title,
      },
    },
    opacity = settings.opacity,
  }
end

local function exit(popup, opts)
  if opts.action_before_exit and opts.cb ~= nil then
    opts.cb()
    popup:unmount()
  else
    popup:unmount()
    if opts.cb ~= nil then
      opts.cb()
    end
  end
end

-- These keymaps are buffer specific and are set dynamically when popups mount
M.set_popup_keymaps = function(popup, action, linewise_action, opts)
  local settings = require("gitlab.state").settings
  if settings.keymaps.disable_all or settings.keymaps.popup.disable_all then
    return
  end

  if opts == nil then
    opts = {}
  end
  if action ~= "Help" and settings.keymaps.help then -- Don't show help on the help popup
    vim.keymap.set("n", settings.keymaps.help, function()
      local help = require("gitlab.actions.help")
      help.open()
    end, { buffer = popup.bufnr, desc = "Open help", nowait = settings.keymaps.help_nowait })
  end
  if action ~= nil and settings.keymaps.popup.perform_action then
    vim.keymap.set("n", settings.keymaps.popup.perform_action, function()
      local text = u.get_buffer_text(popup.bufnr)
      if opts.action_before_close then
        action(text, popup.bufnr)
        exit(popup, opts)
      else
        exit(popup, opts)
        action(text, popup.bufnr)
      end
    end, { buffer = popup.bufnr, desc = "Perform action", nowait = settings.keymaps.popup.perform_action_nowait })
  end

  if linewise_action ~= nil and settings.keymaps.popup.perform_action then
    vim.keymap.set("n", settings.keymaps.popup.perform_linewise_action, function()
      local bufnr = vim.api.nvim_get_current_buf()
      local linnr = vim.api.nvim_win_get_cursor(0)[1]
      local text = u.get_line_content(bufnr, linnr)
      linewise_action(text)
    end, {
      buffer = popup.bufnr,
      desc = "Perform linewise action",
      nowait = settings.keymaps.popup.perform_linewise_action_nowait,
    })
  end

  if settings.keymaps.popup.discard_changes then
    vim.keymap.set("n", settings.keymaps.popup.discard_changes, function()
      local temp_registers = settings.popup.temp_registers
      settings.popup.temp_registers = {}
      vim.cmd("quit!")
      settings.popup.temp_registers = temp_registers
    end, {
      buffer = popup.bufnr,
      desc = "Quit discarding changes",
      nowait = settings.keymaps.popup.discard_changes_nowait,
    })
  end

  if opts.save_to_temp_register then
    vim.api.nvim_create_autocmd("BufWinLeave", {
      buffer = popup.bufnr,
      callback = function()
        local text = u.get_buffer_text(popup.bufnr)
        for _, register in ipairs(settings.popup.temp_registers) do
          vim.fn.setreg(register, text)
        end
      end,
    })
  end

  if opts.action_before_exit then
    vim.api.nvim_create_autocmd("BufWinLeave", {
      buffer = popup.bufnr,
      callback = function()
        exit(popup, opts)
      end,
    })
  end
end

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
      popup:update_layout(opts and M.create_popup_state(unpack(opts)))
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
