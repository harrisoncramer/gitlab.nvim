local M = {}

M.show_popup = function(char)
  -- Close existing popup if it's open
  if M.popup_win_id and vim.api.nvim_win_is_valid(M.popup_win_id) then
    vim.api.nvim_win_close(M.popup_win_id, true)
  end

  -- Create a buffer for the popup window
  local buf = vim.api.nvim_create_buf(false, true)

  -- Set the content of the popup buffer to the character
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { char })

  -- Define the popup window options
  local opts = {
    relative = "cursor",
    row = -2,
    col = 0,
    width = 2, -- Width set to 2 to accommodate the border
    height = 1,
    style = "minimal",
    border = "single",
  }

  -- Open the popup window and store its ID
  M.popup_win_id = vim.api.nvim_open_win(buf, false, opts)
end

M.close_popup = function()
  if M.popup_win_id and vim.api.nvim_win_is_valid(M.popup_win_id) then
    vim.api.nvim_win_close(M.popup_win_id, true)
    M.popup_win_id = nil -- Reset the window ID
  end
end

M.init = function()
  -- Set up autocommands
  vim.api.nvim_create_autocmd({ "CursorHold" }, {
    callback = function()
      -- Get the current cursor position
      local row, col = unpack(vim.api.nvim_win_get_cursor(0))
      row = row - 1 -- Adjust row because Lua is 1-indexed
      col = col - 2 -- Adjust to account for > at front of line

      if col < 1 then
        return
      end

      -- Get the text of the current line
      local line = vim.api.nvim_buf_get_lines(0, row, row + 1, false)[1]

      -- Correctly handle multi-byte characters, such as emojis
      local byteIndexStart = vim.str_byteindex(line, col)
      local byteIndexEnd = vim.str_byteindex(line, col + 1)

      -- Extract the character (or emoji) under the cursor
      local char = line:sub(byteIndexStart + 1, byteIndexEnd)

      -- Proceed only if char is not empty (to avoid empty popups)
      if char == "" then
        return
      end

      M.show_popup(char)
    end,
    buffer = vim.api.nvim_get_current_buf(),
  })

  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    callback = function()
      M.close_popup()
    end,
    buffer = vim.api.nvim_get_current_buf(),
  })
end

return M
