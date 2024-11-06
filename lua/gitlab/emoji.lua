local u = require("gitlab.utils")
local common = require("gitlab.actions.common")
local state = require("gitlab.state")

local M = {
  ---@type EmojiMap|nil
  emoji_map = {},
  ---@type Emoji[]
  emoji_list = {},
}

M.init = function()
  local root_path = state.settings.root_path
  local emoji_path = root_path
    .. state.settings.file_separator
    .. "cmd"
    .. state.settings.file_separator
    .. "config"
    .. state.settings.file_separator
    .. "emojis.json"
  local emojis = u.read_file(emoji_path)
  if emojis == nil then
    u.notify("Could not read emoji file at " .. emoji_path, vim.log.levels.WARN)
  end

  local data_ok, data = pcall(vim.json.decode, emojis)
  if not data_ok then
    u.notify("Could not parse emoji file at " .. emoji_path, vim.log.levels.WARN)
  end

  M.emoji_map = data
  M.emoji_list = {}
  for _, v in pairs(M.emoji_map) do
    table.insert(M.emoji_list, v)
  end
end

-- Define the popup window options
M.popup_opts = {
  relative = "cursor",
  row = -2,
  col = 0,
  width = 2, -- Width set dynamically later
  height = 1,
  style = "minimal",
  border = "single",
}

M.show_popup = function(char)
  -- Close existing popup if it's open
  if M.popup_win_id and vim.api.nvim_win_is_valid(M.popup_win_id) then
    vim.api.nvim_win_close(M.popup_win_id, true)
  end

  -- Create a buffer for the popup window
  local buf = vim.api.nvim_create_buf(false, true)

  -- Set the content of the popup buffer to the character
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { char })

  -- Open the popup window and store its ID
  M.popup_win_id = vim.api.nvim_open_win(buf, false, M.popup_opts)
end

M.close_popup = function()
  if M.popup_win_id and vim.api.nvim_win_is_valid(M.popup_win_id) then
    vim.api.nvim_win_close(M.popup_win_id, true)
    M.popup_win_id = nil -- Reset the window ID
  end
end

M.init_popup = function(tree, bufnr)
  vim.api.nvim_create_autocmd({ "CursorHold" }, {
    callback = function()
      local node = tree:get_node()
      if node == nil or not common.is_node_note(node) then
        return
      end

      local note_node = common.get_note_node(tree, node)
      local root_node = common.get_root_node(tree, node)
      local note_id_str = tostring(note_node.is_root and root_node.root_note_id or note_node.id)
      local emojis = state.DISCUSSION_DATA.emojis

      local note_emojis = emojis[note_id_str]
      if note_emojis == nil then
        return
      end

      local cursor_pos = vim.api.nvim_win_get_cursor(0)
      -- "zyiw on the next line erases the unnamed register. This may interfere with the
      -- `temp_registers` used for backing up editable popup contents, so let's backup the unnamed
      -- register.
      local unnamed_register_contents = vim.fn.getreg('"')
      vim.api.nvim_command('normal! "zyiw')
      vim.api.nvim_win_set_cursor(0, cursor_pos)
      local word = vim.fn.getreg("z")
      vim.fn.setreg('"', unnamed_register_contents) -- restore the unnamed register

      for k, v in pairs(M.emoji_map) do
        if v.moji == word then
          local names = M.get_users_who_reacted_with_emoji(k, note_emojis)
          M.popup_opts.width = string.len(names)
          if M.popup_opts.width > 0 then
            M.show_popup(names)
          end
        end
      end
    end,
    buffer = bufnr,
  })

  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    callback = function()
      M.close_popup()
    end,
    buffer = bufnr,
  })
end

---@param name string
---@return string
M.get_users_who_reacted_with_emoji = function(name, note_emojis)
  local result = ""
  for _, v in pairs(note_emojis) do
    if v.name == name then
      result = result .. v.user.name .. ", "
    end
  end
  return string.len(result) > 3 and result:sub(1, -3) or result
end

M.pick_emoji = function(options, cb)
  vim.ui.select(options, {
    prompt = "Choose emoji",
    format_item = function(val)
      if type(state.settings.emojis.formatter) == "function" then
        return state.settings.emojis.formatter(val)
      end
      return string.format("%s %s", val.moji, val.name)
    end,
  }, function(choice)
    if not choice then
      return
    end
    local name = choice.shortname:sub(2, -2)
    cb(name, choice)
  end)
end

return M
