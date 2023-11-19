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
  reviewer = "diffview",
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
  discussion_sign_and_diagnostic = {
    skip_resolved_discussion = false,
    skip_old_revision_discussion = false,
  },
  discussion_sign = {
    -- See :h sign_define for details about sign configuration.
    enabled = true,
    text = "💬",
    linehl = nil,
    texthl = nil,
    culhl = nil,
    numhl = nil,
    priority = 20,
    helper_signs = {
      -- For multiline comments the helper signs are used to indicate the whole context
      -- Priority of helper signs is lower than the main sign (-1).
      enabled = true,
      start = "↑",
      mid = "|",
      ["end"] = "↓",
    },
  },
  discussion_diagnostic = {
    -- If you want to customize diagnostics for discussions you can make special config
    -- for namespace `gitlab_discussion`. See :h vim.diagnostic.config
    enabled = true,
    severity = vim.diagnostic.severity.INFO,
    code = nil, -- see :h diagnostic-structure
    display_opts = {}, -- this is dirrectly used as opts in vim.diagnostic.set, see :h vim.diagnostic.config.
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
  go_server_running = false,
  is_gitlab_project = false,
  colors = {
    discussion_tree = {
      username = "Keyword",
      date = "Comment",
      chevron = "Comment",
    },
  },
}

-- Merges user settings into the default settings, overriding them
M.merge_settings = function(args)
  M.settings = u.merge(M.settings, args)

  -- Check deprecated settings and alert users!
  if M.settings.dialogue ~= nil then
    u.notify("The dialogue field has been deprecated, please remove it from your setup function", vim.log.levels.WARN)
  end

  if M.settings.reviewer == "delta" then
    u.notify(
      "Delta is no longer a supported reviewer, please use diffview and update your setup function",
      vim.log.levels.ERROR
    )
    return false
  end

  local diffview_ok, _ = pcall(require, "diffview")
  if not diffview_ok then
    u.notify("Please install diffview, it is required")
    return false
  end

  if M.settings.review_pane ~= nil then
    u.notify(
      "The review_pane field is only relevant for Delta, which has been deprecated, please remove it from your setup function",
      vim.log.levels.WARN
    )
  end

  M.settings.file_separator = (u.is_windows() and "\\" or "/")

  return true
end

M.print_settings = function()
  vim.print(M.settings)
end

-- First reads environment variables into the settings module,
-- then attemps to read a `.gitlab.nvim` configuration file.
-- If after doing this, any variables are missing, alerts the user.
-- The `.gitlab.nvim` configuration file takes precedence.
M.setPluginConfiguration = function()
  if M.initialized then
    return true
  end

  local base_path = vim.fn.trim(vim.fn.system({ "git", "rev-parse", "--show-toplevel" }))
  if vim.v.shell_error ~= 0 then
    u.notify(string.format("Could not get base directory: %s", base_path), vim.log.levels.ERROR)
    return false
  end

  local config_file_path = base_path .. M.settings.file_separator .. ".gitlab.nvim"

  local config_file_content = u.read_file(config_file_path)

  local file_properties = {}
  if config_file_content ~= nil then
    local file = assert(io.open(config_file_path, "r"))
    for line in file:lines() do
      for key, value in string.gmatch(line, "(.-)=(.-)$") do
        file_properties[key] = value
      end
    end
  end

  M.settings.auth_token = file_properties.auth_token or os.getenv("GITLAB_TOKEN")
  M.settings.gitlab_url = file_properties.gitlab_url or os.getenv("GITLAB_URL") or "https://gitlab.com"

  if M.settings.auth_token == nil then
    vim.notify(
      "Missing authentication token for Gitlab, please provide it as an environment variable or in the .gitlab.nvim file",
      vim.log.levels.ERROR
    )
    return false
  end

  M.initialized = true
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
