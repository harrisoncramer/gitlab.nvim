-- This module is responsible for holding and setting shared state between
-- modules, such as keybinding data and other settings and configuration.
-- This module is also responsible for ensuring that the state of the plugin
-- is valid via dependencies

local u = require("gitlab.utils")
local M = {}

M.emoji_map = nil

-- These are the default settings for the plugin
M.settings = {
  port = nil, -- choose random port
  debug = { go_request = false, go_response = false },
  log_path = (vim.fn.stdpath("cache") .. "/gitlab.nvim.log"),
  config_path = nil,
  reviewer = "diffview",
  reviewer_settings = {
    diffview = {
      imply_local = false,
    },
  },
  connection_settings = {
    insecure = true,
  },
  attachment_dir = "",
  help = "g?",
  popup = {
    perform_action = "<leader>s",
    perform_linewise_action = "<leader>l",
    width = "40%",
    height = "60%",
    border = "rounded",
    opacity = 1.0,
    edit = nil,
    reply = nil,
    comment = nil,
    note = nil,
    help = nil,
    pipeline = nil,
    squash_message = nil,
  },
  discussion_tree = {
    auto_open = true,
    switch_view = "S",
    default_view = "discussions",
    blacklist = {},
    jump_to_file = "o",
    jump_to_reviewer = "m",
    edit_comment = "e",
    delete_comment = "dd",
    open_in_browser = "b",
    reply = "r",
    toggle_node = "t",
    add_emoji = "Ea",
    delete_emoji = "Ed",
    toggle_all_discussions = "T",
    toggle_resolved_discussions = "R",
    toggle_unresolved_discussions = "U",
    keep_current_open = false,
    toggle_resolved = "p",
    relative = "editor",
    position = "left",
    size = "20%",
    resolved = "✓",
    unresolved = "-",
    tree_type = "simple",
    toggle_tree_type = "i",
    ---@param t WinbarTable
    winbar = function(t)
      local discussions_content = t.resolvable_discussions ~= 0
          and string.format("Discussions (%d/%d)", t.resolved_discussions, t.resolvable_discussions)
        or "Discussions"
      local notes_content = t.resolvable_notes ~= 0
          and string.format("Notes (%d/%d)", t.resolved_notes, t.resolvable_notes)
        or "Notes"
      if t.name == "Discussions" then
        notes_content = "%#Comment#" .. notes_content
        discussions_content = "%#Text#" .. discussions_content
      else
        discussions_content = "%#Comment#" .. discussions_content
        notes_content = "%#Text#" .. notes_content
      end
      local help = "%#Comment#%=Help: " .. t.help_keymap:gsub(" ", "<space>") .. " "
      return " " .. discussions_content .. " %#Comment#| " .. notes_content .. help
    end,
  },
  merge = {
    squash = false,
    delete_branch = false,
  },
  create_mr = {
    target = nil,
    template_file = nil,
    delete_branch = false,
    squash = false,
    title_input = {
      width = 40,
      border = "rounded",
    },
  },
  info = {
    enabled = true,
    horizontal = false,
    fields = {
      "author",
      "created_at",
      "updated_at",
      "merge_status",
      "draft",
      "conflicts",
      "assignees",
      "reviewers",
      "pipeline",
      "branch",
      "target_branch",
      "delete_branch",
      "squash",
      "labels",
    },
  },
  discussion_signs = {
    enabled = true,
    skip_resolved_discussion = false,
    severity = vim.diagnostic.severity.INFO,
    virtual_text = false,
    icons = {
      comment = "→|",
      range = " |",
    },
    skip_old_revision_discussion = false,
    priority = 100,
  },
  pipeline = {
    created = "",
    pending = "",
    preparing = "",
    scheduled = "",
    running = "",
    canceled = "↪",
    skipped = "↪",
    success = "✓",
    failed = "",
  },
  go_server_running = false,
  is_gitlab_project = false,
  colors = {
    discussion_tree = {
      username = "Keyword",
      date = "Comment",
      chevron = "DiffviewNonText",
      directory = "Directory",
      directory_icon = "DiffviewFolderSign",
      file_name = "Normal",
      resolved = "DiagnosticSignOk",
      unresolved = "DiagnosticSignWarn",
    },
  },
}

-- These are the initial states of the discussion trees
M.discussion_tree = {
  resolved_expanded = false,
  unresolved_expanded = false,
}
M.unlinked_discussion_tree = {
  resolved_expanded = false,
  unresolved_expanded = false,
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

  local base_path
  if M.settings.config_path ~= nil then
    base_path = M.settings.config_path
  else
    base_path = vim.fn.trim(vim.fn.system({ "git", "rev-parse", "--show-toplevel" }))
    if vim.v.shell_error ~= 0 then
      u.notify(string.format("Could not get base directory: %s", base_path), vim.log.levels.ERROR)
      return false
    end
  end

  local config_file_path = base_path .. M.settings.file_separator .. ".gitlab.nvim"
  local config_file_content = u.read_file(config_file_path, { remove_newlines = true })

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
  M.settings.gitlab_url = u.trim_slash(file_properties.gitlab_url or os.getenv("GITLAB_URL") or "https://gitlab.com")

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
  if opts == nil then
    opts = {}
  end
  if action ~= "Help" then -- Don't show help on the help popup
    vim.keymap.set("n", M.settings.help, function()
      local help = require("gitlab.actions.help")
      help.open()
    end, { buffer = popup.bufnr, desc = "Open help" })
  end
  if action ~= nil then
    vim.keymap.set("n", M.settings.popup.perform_action, function()
      local text = u.get_buffer_text(popup.bufnr)
      if opts.action_before_close then
        action(text, popup.bufnr)
        exit(popup, opts)
      else
        exit(popup, opts)
        action(text, popup.bufnr)
      end
    end, { buffer = popup.bufnr, desc = "Perform action" })
  end

  if linewise_action ~= nil then
    vim.keymap.set("n", M.settings.popup.perform_linewise_action, function()
      local bufnr = vim.api.nvim_get_current_buf()
      local linnr = vim.api.nvim_win_get_cursor(0)[1]
      local text = u.get_line_content(bufnr, linnr)
      linewise_action(text)
    end, { buffer = popup.bufnr, desc = "Perform linewise action" })
  end

  vim.api.nvim_create_autocmd("BufUnload", {
    buffer = popup.bufnr,
    callback = function()
      exit(popup, opts)
    end,
  })
end

-- Dependencies
-- These tables are passed to the async.sequence function, which calls them in sequence
-- before calling an action. They are used to set global state that's required
-- for each of the actions to occur. This is necessary because some Gitlab behaviors (like
-- adding a reviewer) requires some initial state.
M.dependencies = {
  user = { endpoint = "/users/me", key = "user", state = "USER", refresh = false },
  info = { endpoint = "/mr/info", key = "info", state = "INFO", refresh = false },
  latest_pipeline = { endpoint = "/pipeline", key = "latest_pipeline", state = "PIPELINE", refresh = true },
  labels = { endpoint = "/mr/label", key = "labels", state = "LABELS", refresh = false },
  revisions = { endpoint = "/mr/revisions", key = "Revisions", state = "MR_REVISIONS", refresh = false },
  project_members = {
    endpoint = "/project/members",
    key = "ProjectMembers",
    state = "PROJECT_MEMBERS",
    refresh = false,
  },
}

-- This function clears out all of the previously fetched data. It's used
-- to reset the plugin state when the Go server is restarted
M.clear_data = function()
  M.INFO = nil
  for _, dep in ipairs(M.dependencies) do
    M[dep.state] = nil
  end
end

return M
