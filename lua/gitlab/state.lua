-- This module is responsible for holding and setting shared state between
-- modules, such as keybinding data and other settings and configuration.
-- This module is also responsible for ensuring that the state of the plugin
-- is valid via dependencies

local git = require("gitlab.git")
local u = require("gitlab.utils")
local M = {}

M.emoji_map = nil

---Returns a gitlab token, and a gitlab URL. Used to connect to gitlab.
---@return string|nil, string|nil, string|nil
M.default_auth_provider = function()
  local base_path, err = M.settings.config_path, nil
  if base_path == nil then
    base_path, err = git.base_dir()
  end

  if err ~= nil then
    return "", ""
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

  local auth_token = file_properties.auth_token or os.getenv("GITLAB_TOKEN")
  local gitlab_url = file_properties.gitlab_url or os.getenv("GITLAB_URL")

  return auth_token, gitlab_url, err
end

-- These are the default settings for the plugin
M.settings = {
  auth_provider = M.default_auth_provider,
  port = nil, -- choose random port
  debug = {
    go_request = false,
    go_response = false,
  },
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
    keymaps = {
      next_field = "<Tab>",
      prev_field = "<S-Tab>",
    },
    perform_action = "<leader>s",
    perform_linewise_action = "<leader>l",
    width = "40%",
    height = "60%",
    border = "rounded",
    opacity = 1.0,
    edit = nil,
    comment = nil,
    note = nil,
    help = nil,
    pipeline = nil,
    reply = nil,
    squash_message = nil,
    temp_registers = {},
  },
  discussion_tree = {
    chevrons = { " ", " ", "  " },
    auto_open = true,
    switch_view = "S",
    default_view = "discussions",
    blacklist = {},
    jump_to_file = "o",
    jump_to_reviewer = "m",
    edit_comment = "e",
    delete_comment = "dd",
    refresh_data = "a",
    reply = "r",
    toggle_node = "t",
    add_emoji = "Ea",
    delete_emoji = "Ed",
    toggle_all_discussions = "T",
    toggle_resolved_discussions = "R",
    toggle_unresolved_discussions = "U",
    keep_current_open = false,
    publish_draft = "P",
    toggle_resolved = "p",
    position = "left",
    open_in_browser = "b",
    copy_node_url = "u",
    size = "20%",
    relative = "editor",
    resolved = "✓",
    unresolved = "-",
    tree_type = "simple",
    toggle_tree_type = "i",
    draft_mode = false,
    toggle_draft_mode = "D",
  },
  create_mr = {
    target = nil,
    template_file = nil,
    delete_branch = false,
    squash = false,
    fork = {
      enabled = false,
      forked_project_id = nil,
    },
    title_input = {
      width = 40,
      border = "rounded",
    },
  },
  choose_merge_request = {
    open_reviewer = true,
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
    use_diagnostic_signs = true,
    priority = 100,
    icons = {
      comment = "→|",
      range = " |",
    },
    skip_old_revision_discussion = false,
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
      mention = "WarningMsg",
      date = "Comment",
      chevron = "DiffviewNonText",
      directory = "Directory",
      directory_icon = "DiffviewFolderSign",
      file_name = "Normal",
      resolved = "DiagnosticSignOk",
      unresolved = "DiagnosticSignWarn",
      draft = "DiffviewNonText",
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

  local token, url, err = M.settings.auth_provider()
  if err ~= nil then
    return
  end

  M.settings.auth_token = token
  M.settings.gitlab_url = u.trim_slash(url or "https://gitlab.com")

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

  if opts.save_to_temp_register then
    vim.api.nvim_create_autocmd("BufWinLeave", {
      buffer = popup.bufnr,
      callback = function()
        local text = u.get_buffer_text(popup.bufnr)
        for _, register in ipairs(M.settings.popup.temp_registers) do
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

-- Dependencies
-- These tables are passed to the async.sequence function, which calls them in sequence
-- before calling an action. They are used to set global state that's required
-- for each of the actions to occur. This is necessary because some Gitlab behaviors (like
-- adding a reviewer) requires some initial state.
M.dependencies = {
  user = {
    endpoint = "/users/me",
    key = "user",
    state = "USER",
    refresh = false,
  },
  info = {
    endpoint = "/mr/info",
    key = "info",
    state = "INFO",
    refresh = false,
  },
  latest_pipeline = {
    endpoint = "/pipeline",
    key = "latest_pipeline",
    state = "PIPELINE",
    refresh = true,
  },
  labels = {
    endpoint = "/mr/label",
    key = "labels",
    state = "LABELS",
    refresh = false,
  },
  revisions = {
    endpoint = "/mr/revisions",
    key = "Revisions",
    state = "MR_REVISIONS",
    refresh = false,
  },
  draft_notes = {
    endpoint = "/mr/draft_notes/",
    key = "draft_notes",
    state = "DRAFT_NOTES",
    refresh = false,
  },
  project_members = {
    endpoint = "/project/members",
    key = "ProjectMembers",
    state = "PROJECT_MEMBERS",
    refresh = false,
  },
  merge_requests = {
    endpoint = "/merge_requests",
    key = "merge_requests",
    state = "MERGE_REQUESTS",
    refresh = false,
  },
  discussion_data = {
    -- key is missing here...
    endpoint = "/mr/discussions/list",
    state = "DISCUSSION_DATA",
    refresh = false,
    method = "POST",
    body = function()
      return {
        blacklist = M.settings.discussion_tree.blacklist,
      }
    end,
  },
}

M.load_new_state = function(dep, cb)
  local job = require("gitlab.job")
  local dependency = M.dependencies[dep]
  job.run_job(
    dependency.endpoint,
    dependency.method or "GET",
    dependency.body and dependency.body() or nil,
    function(data)
      if dependency.key then
        M[dependency.state] = u.ensure_table(data[dependency.key])
      end
      if type(cb) == "function" then
        cb(data) -- To set data manually...
      end
    end
  )
end

-- This function clears out all of the previously fetched data. It's used
-- to reset the plugin state when the Go server is restarted
M.clear_data = function()
  M.INFO = nil
  for _, dep in ipairs(M.dependencies) do
    M[dep.state] = nil
  end
end

return M
