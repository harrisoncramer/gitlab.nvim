local discussions = require("gitlab.actions.discussions")
local u = require("gitlab.utils")
local state = require("gitlab.state")
local M = {}

M.init = function()
  local bin_path = state.settings.bin_path
  local emoji_path = bin_path ..
      state.settings.file_separator ..
      "config" ..
      state.settings.file_separator ..
      "emojis.json"
  local emojis = u.read_file(emoji_path)
  if emojis == nil then
    u.notify("Could not read emoji file at " .. emoji_path, vim.log.levels.WARN)
  end

  local data_ok, data = pcall(vim.json.decode, emojis)
  if not data_ok then
    u.notify("Could not parse emoji file at " .. emoji_path, vim.log.levels.WARN)
  end

  state.emoji_map = data
end

return M
