local u = require("gitlab.utils")
local common = require("gitlab.actions.common")

-- Basic emoji aliases that are missing in Gitlab's list.
---@type Emoji
local thumbsup = { name = "+1", shortname = ":+1:", moji = "👍", category = "People & Body" }
---@type Emoji
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

---Show the popup with user names.
---@param names string The names of the users who awarded this emoji as a comma-separated string
M.show_popup = function(names)
  -- Close existing popup if it's open
  if M.popup_win_id and vim.api.nvim_win_is_valid(M.popup_win_id) then
    vim.api.nvim_win_close(M.popup_win_id, true)
  end

  -- Create a buffer for the popup window
  local buf = vim.api.nvim_create_buf(false, true)

  -- Set the content of the popup buffer to the character
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { names })

  -- Open the popup window and store its ID
  M.popup_win_id = vim.api.nvim_open_win(buf, false, M.popup_opts)
end

---Close the popup and clear the state.
M.close_popup = function()
  if M.popup_win_id and vim.api.nvim_win_is_valid(M.popup_win_id) then
    vim.api.nvim_win_close(M.popup_win_id, true)
    M.popup_win_id = nil -- Reset the window ID
  end
end

---Set up autocommand to show popup with emoji awarder name.
---TODO: This autocommand iterates over the full emoji map on each CursorHold.
---This could be more efficiency (and possibly in a more user-friendly way) be
---implemented as diagnostics: Emojis would only be recalculated on tree changes and
---we'd get navigation to emojis and showing a popup for free (]d, [d, <c-w>d).
---@param tree NuiTree
---@param bufnr integer The number of the buffer that holds the discussion tree
M.init_popup = function(tree, bufnr)
  vim.api.nvim_create_autocmd({ "CursorHold" }, {
    callback = function()
      local node = common.get_current_node(tree)
      if node == nil or not common.is_node_note(node) then
        return
      end

      local note_node = common.get_note_node(tree, node)
      local root_node = common.get_root_node(tree, node)
      if note_node == nil or root_node == nil then
        u.notify("Could not get note or root node of comment", vim.log.levels.ERROR)
        return
      end

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

---@class NoteEmoji
---@field awardable_id integer ID of the note for which emoji was awarded, e.g., 3244783717
---@field awardable_type string E.g., "Note"
---@field created_at string Time on which the emoji was created, e.g., "2026-07-06T16:28:14.039Z"
---@field id integer ID of the emoji, e.g., 50933088
---@field name string The short emoji name "thumbsup"
---@field updated_at string Time on which the emoji was updated, e.g., "2026-07-06T16:28:14.039Z"
---@field user Author The user who awarded the emoji

---Return the names of the users who awarded this emoji as a comma-separated string.
---@param emoji_name string
---@param note_emojis NoteEmoji[]
---@return string
M.get_users_who_reacted_with_emoji = function(emoji_name, note_emojis)
  local result = ""
  for _, v in pairs(note_emojis) do
    if v.name == emoji_name then
      result = result .. v.user.name .. ", "
    end
  end
  return string.len(result) > 3 and result:sub(1, -3) or result
end

---Prompt user to pick an emoji from a list and run callback on the selection.
---@param emojis Emoji[] The list of emojis to pick from
---@param cb fun(name: string) The callback that will run after selecting an emoji. It is passed the emoji's shortname without the surrounding colons as an argument, e.g., ("thumbsup")
M.pick_emoji = function(emojis, cb)
  local settings = require("gitlab.state").settings
  vim.ui.select(emojis, {
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
    cb(name)
  end)
end

return M
