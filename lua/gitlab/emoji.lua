local u = require("gitlab.utils")
local common = require("gitlab.actions.common")

-- Basic emoji aliases that are missing in Gitlab's list.
local thumbsup = { name = "+1", shortname = ":+1:", moji = "👍", category = "People & Body" }
local thumbsdown = { name = "-1", shortname = ":-1:", moji = "👎", category = "People & Body" }

local M = {
  ---@type EmojiMap
  emoji_map = { ["+1"] = thumbsup, ["-1"] = thumbsdown },
  ---@type Emoji[]
  emoji_list = { thumbsup, thumbsdown },
}

-- Fetch emojis from Gitlab and make them available in the plugin.
M.init = function()
  local settings = require("gitlab.state").settings
  local version = type(settings.emojis.version) == "function" and settings.emojis.version(settings.gitlab_url)
    or settings.emojis.version
  local emojis_url = settings.gitlab_url .. "/-/emojis/" .. version .. "/emojis.json"
  local command = { "curl", emojis_url }
  vim.system(command, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        require("gitlab.utils").notify(result.stderr, vim.log.levels.ERROR)
      else
        local data_ok, data = pcall(vim.json.decode, result.stdout)
        if not data_ok then
          local message = "Could not get emojis from "
            .. emojis_url
            .. (data ~= nil and string.format(". JSON.decode error: %s", data) or "")
          u.notify(message, vim.log.levels.ERROR)
          u.notify(result.stdout, vim.log.levels.DEBUG)
          return
        end
        for _, v in ipairs(data or {}) do
          local emoji = { name = v.d, shortname = string.format(":%s:", v.n), moji = v.e, category = v.c }
          M.emoji_map[v.n] = emoji
          table.insert(M.emoji_list, emoji)
        end
      end
    end)
  end)
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
      local emojis = require("gitlab.state").DISCUSSION_DATA.emojis

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
  local settings = require("gitlab.state").settings
  vim.ui.select(options, {
    prompt = "Choose emoji",
    format_item = function(val)
      if type(settings.emojis.formatter) == "function" then
        return settings.emojis.formatter(val)
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
