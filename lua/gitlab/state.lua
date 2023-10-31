-- This module is responsible for holding and setting shared state between
-- modules, such as keybinding data and other settings and configuration.
-- This module is also responsible for ensuring that the state of the plugin
-- is valid via dependencies

local u = require("gitlab.utils")
local M = {}

-- These are the default settings for the plugin
M.settings = {
  port = nil, -- choose random port
  debug = { go_request = false, go_response = false },
  log_path = (vim.fn.stdpath("cache") .. "/gitlab.nvim.log"),
  reviewer = "delta",
  attachment_dir = "",
  popup = {
    exit = "<Esc>",
    perform_action = "<leader>s",
    perform_linewise_action = "<leader>l",
  },
  discussion_tree = {
    blacklist = {},
    jump_to_file = "o",
    jump_to_reviewer = "m",
    edit_comment = "e",
    delete_comment = "dd",
    reply = "r",
    toggle_node = "t",
    toggle_resolved = "p",
    relative = "editor",
    position = "left",
    size = "20%",
    resolved = "✓",
    unresolved = "",
  },
  review_pane = {
    delta = {
      added_file = "",
      modified_file = "",
      removed_file = "",
    },
  },
  pipeline = {
    created = "",
    pending = "",
    preparing = "",
    scheduled = "",
    running = "ﰌ",
    canceled = "ﰸ",
    skipped = "ﰸ",
    success = "✓",
    failed = "",
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
M.merge_settings = function(args)
  if args == nil then
    return
  end
  M.settings = u.merge(M.settings, args)
end

M.print_settings = function()
  u.P(M.settings)
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

local function exit(popup, cb)
  popup:unmount()
  if cb ~= nil then
    cb()
  end
end

-- These keymaps are buffer specific and are set dynamically when popups mount
M.set_popup_keymaps = function(popup, action, linewise_action, opts)
  if opts == nil then
    opts = {}
  end
  vim.keymap.set("n", M.settings.popup.exit, function()
    exit(popup, opts.cb)
  end, { buffer = popup.bufnr })
  if action ~= nil then
    vim.keymap.set("n", M.settings.popup.perform_action, function()
      local text = u.get_buffer_text(popup.bufnr)
      if opts.action_before_close then
        action(text, popup.bufnr)
        exit(popup)
      else
        exit(popup)
        action(text, popup.bufnr)
      end
    end, { buffer = popup.bufnr })
  end

  if linewise_action ~= nil then
    vim.keymap.set("n", M.settings.popup.perform_linewise_action, function()
      local bufnr = vim.api.nvim_get_current_buf()
      local linnr = vim.api.nvim_win_get_cursor(0)[1]
      local text = u.get_line_content(bufnr, linnr)
      linewise_action(text)
    end, { buffer = popup.bufnr })
  end
end

-- Dependencies
-- These tables are passed to the async.sequence function, which calls them in sequence
-- before calling an action. They are used to set global state that's required
-- for each of the actions to occur. This is necessary because some Gitlab behaviors (like
-- adding a reviewer) requires some initial state.
M.dependencies = {
  info = { endpoint = "/info", key = "info", state = "INFO", refresh = false },
  revisions = { endpoint = "/mr/revisions", key = "Revisions", state = "MR_REVISIONS", refresh = false },
  project_members = { endpoint = "/members", key = "ProjectMembers", state = "PROJECT_MEMBERS", refresh = false },
}

return M
