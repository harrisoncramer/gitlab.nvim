-- This module is responsible for holding and setting shared state between
-- modules, such as keybinding data and other settings and configuration.
-- This module is also responsible for "ensuring" that the state of the plugin
-- is valid with the ensure functions.

local u                  = require("gitlab.utils")
local M                  = {}

-- These are the default settings for the plugin
M.settings               = {
  port = 21036,
  log_path = (vim.fn.stdpath("cache") .. "/gitlab.nvim.log"),
  popup = {
    exit = "<Esc>",
    perform_action = "<leader>s",
  },
  discussion_tree = {
    jump_to_location = "o",
    edit_comment = "e",
    delete_comment = "dd",
    reply_to_comment = "r",
    toggle_node = "t",
    toggle_resolved = "p",
    relative = "editor",
    position = "left",
    size = "20%",
    resolved = '✓',
    unresolved = ''
  },
  review_pane = {
    toggle_discussions = "<leader>d",
    added_file = "",
    modified_file = "",
    removed_file = "",
  },
  dialogue = {
    focus_next = { "j", "<Down>", "<Tab>" },
    focus_prev = { "k", "<Up>", "<S-Tab>" },
    close = { "<Esc>", "<C-c>" },
    submit = { "<CR>", "<Space>" },
  },
  go_server_running = false,
  is_gitlab_project = false,
}

-- Merges user settings into the default settings, overriding them
M.merge_settings         = function(args)
  if args == nil then return end
  M.settings = u.merge_tables(M.settings, args)
end

M.print_settings         = function()
  P(M.settings)
end

-- Merges `.gitlab.nvim` settings into the state module
M.setPluginConfiguration = function()
  local config_file_path = vim.fn.getcwd() .. "/.gitlab.nvim"
  local config_file_content = u.read_file(config_file_path)
  if config_file_content == nil then
    return false
  end

  M.is_gitlab_project = true

  local file = assert(io.open(config_file_path, "r"))
  local properties = {}
  for line in file:lines() do
    for key, value in string.gmatch(line, "(.-)=(.-)$") do
      properties[key] = value
    end
  end

  M.settings.project_id = properties.project_id
  M.settings.auth_token = properties.auth_token or os.getenv("GITLAB_TOKEN")
  M.settings.gitlab_url = properties.gitlab_url or "https://gitlab.com"

  if M.settings.auth_token == nil then
    error("Missing authentication token for Gitlab")
  end

  if M.settings.project_id == nil then
    error("Missing project ID in .gitlab.nvim file.")
  end

  if type(tonumber(M.settings.project_id)) ~= "number" then
    error("The .gitlab.nvim project file's 'project_id' must be number")
  end

  return true
end

-- These keymaps are buffer specific and are set dynamically when popups mount
M.set_popup_keymaps      = function(popup, action)
  vim.keymap.set('n', M.settings.popup.exit, function() popup:unmount() end, { buffer = true })
  if action ~= nil then
    vim.keymap.set('n', M.settings.popup.perform_action, function()
      local text = u.get_buffer_text(popup.bufnr)
      popup:unmount()
      action(text)
    end, { buffer = true })
  end
end


return M
