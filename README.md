# gitlab.nvim

This Neovim plugin is designed to make it easy to review Gitlab MRs from within the editor. This means you can do things like:

- Create, approve, and merge MRs for the current branch
- Read and edit an MR description
- Add or remove reviewers and assignees
- Resolve, reply to, and unresolve discussion threads
- Create, edit, delete, and reply to comments
- View and manage pipeline Jobs
- Upload files, jump to the browser, and a lot more!

![Screenshot 2024-01-13 at 10 43 32 AM](https://github.com/harrisoncramer/gitlab.nvim/assets/32515581/8dd8b961-a6b5-4e09-b87f-dc4a17b14149)
![Screenshot 2024-01-13 at 10 43 17 AM](https://github.com/harrisoncramer/gitlab.nvim/assets/32515581/079842de-e8a4-45c5-98c2-dcafc799c904)

https://github.com/harrisoncramer/gitlab.nvim/assets/32515581/dc5c07de-4ae6-4335-afe1-d554e3804372

To view these help docs and to get more detailed help information, please run `:h gitlab.nvim`

## Requirements

- <a href="https://go.dev/">Go</a> >= v1.19

## Quick Start

1. Install Go
2. Add configuration (see Installation section)
3. Checkout your feature branch: `git checkout feature-branch`
4. Open Neovim
5. Run `:lua require("gitlab").review()` to open the reviewer pane

For more detailed information about the Lua APIs please run `:h gitlab.nvim.api`

## Installation

With <a href="https://github.com/folke/lazy.nvim">Lazy</a>:

```lua
return {
  "harrisoncramer/gitlab.nvim",
  dependencies = {
    "MunifTanjim/nui.nvim",
    "nvim-lua/plenary.nvim",
    "sindrets/diffview.nvim",
    "stevearc/dressing.nvim", -- Recommended but not required. Better UI for pickers.
    "nvim-tree/nvim-web-devicons" -- Recommended but not required. Icons in discussion tree.
  },
  enabled = true,
  build = function () require("gitlab.server").build(true) end, -- Builds the Go binary
  config = function()
    require("gitlab").setup()
  end,
}
```

And with Packer:

```lua
use {
  'harrisoncramer/gitlab.nvim',
  requires = {
    "MunifTanjim/nui.nvim",
    "nvim-lua/plenary.nvim",
    "sindrets/diffview.nvim",
    "stevearc/dressing.nvim", -- Recommended but not required. Better UI for pickers.
    "nvim-tree/nvim-web-devicons", -- Recommended but not required. Icons in discussion tree.
  },
  run = function() require("gitlab.server").build(true) end,
  config = function()
    require("gitlab").setup()
  end,
}
```

## Connecting to Gitlab

This plugin requires an <a href="https://docs.gitlab.com/ee/user/profile/personal_access_tokens.html#create-a-personal-access-token">auth token</a> to connect to Gitlab. The token can be set in the root directory of the project in a `.gitlab.nvim` environment file, or can be set via a shell environment variable called `GITLAB_TOKEN` instead. If both are present, the `.gitlab.nvim` file will take precedence.

Optionally provide a GITLAB_URL environment variable (or gitlab_url value in the `.gitlab.nvim` file) to connect to a self-hosted Gitlab instance. This is optional, use ONLY for self-hosted instances. Here's what they'd look like as environment variables:

```bash
export GITLAB_TOKEN="your_gitlab_token"
export GITLAB_URL="https://my-personal-gitlab-instance.com/"
```

And as a `.gitlab.nvim` file:

```
auth_token=your_gitlab_token
gitlab_url=https://my-personal-gitlab-instance.com/
```

The plugin will look for the `.gitlab.nvim` file in the root of the current project by default. However, you may provide a custom path to the configuration file via the `config_path` option. This must be an absolute path to the directory that holds your `.gitlab.nvim` file.

For more settings, please see `:h gitlab.nvim.connecting-to-gitlab`

## Configuring the Plugin

Here is the default setup function. All of these values are optional, and if you call this function with no values the defaults will be used:

```lua
require("gitlab").setup({
  port = nil, -- The port of the Go server, which runs in the background, if omitted or `nil` the port will be chosen automatically
  log_path = vim.fn.stdpath("cache") .. "/gitlab.nvim.log", -- Log path for the Go server
  config_path = nil, -- Custom path for `.gitlab.nvim` file, please read the "Connecting to Gitlab" section
  debug = { go_request = false, go_response = false }, -- Which values to log
  attachment_dir = nil, -- The local directory for files (see the "summary" section)
  reviewer_settings = {
    diffview = {
      imply_local = false, -- If true, will attempt to use --imply_local option when calling |:DiffviewOpen|
    },
  },
  connection_settings = {
    insecure = false, -- Like curl's --insecure option, ignore bad x509 certificates on connection
  },
  help = "g?", -- Opens a help popup for local keymaps when a relevant view is focused (popup, discussion panel, etc)
  popup = { -- The popup for comment creation, editing, and replying
    perform_action = "<leader>s", -- Once in normal mode, does action (like saving comment or editing description, etc)
    perform_linewise_action = "<leader>l", -- Once in normal mode, does the linewise action (see logs for this job, etc)
    width = "40%",
    height = "60%",
    border = "rounded", -- One of "rounded", "single", "double", "solid"
    opacity = 1.0, -- From 0.0 (fully transparent) to 1.0 (fully opaque)
    comment = nil, -- Individual popup overrides, e.g. { width = "60%", height = "80%", border = "single", opacity = 0.85 },
    edit = nil,
    note = nil,
    pipeline = nil,
    reply = nil,
    squash_message = nil,
  },
  discussion_tree = { -- The discussion tree that holds all comments
    auto_open = true, -- Automatically open when the reviewer is opened
    switch_view = "S", -- Toggles between the notes and discussions views
    default_view = "discussions" -- Show "discussions" or "notes" by default
    blacklist = {}, -- List of usernames to remove from tree (bots, CI, etc)
    jump_to_file = "o", -- Jump to comment location in file
    jump_to_reviewer = "m", -- Jump to the location in the reviewer window
    edit_comment = "e", -- Edit comment
    delete_comment = "dd", -- Delete comment
    reply = "r", -- Reply to comment
    toggle_node = "t", -- Opens or closes the discussion
    add_emoji = "Ea" -- Add an emoji to the note/comment
    add_emoji = "Ed" -- Remove an emoji from a note/comment
    toggle_all_discussions = "T", -- Open or close separately both resolved and unresolved discussions
    toggle_resolved_discussions = "R", -- Open or close all resolved discussions
    toggle_unresolved_discussions = "U", -- Open or close all unresolved discussions
    keep_current_open = false, -- If true, current discussion stays open even if it should otherwise be closed when toggling
    toggle_resolved = "p" -- Toggles the resolved status of the whole discussion
    position = "left", -- "top", "right", "bottom" or "left"
    open_in_browser = "b" -- Jump to the URL of the current note/discussion
    size = "20%", -- Size of split
    relative = "editor", -- Position of tree split relative to "editor" or "window"
    resolved = '✓', -- Symbol to show next to resolved discussions
    unresolved = '-', -- Symbol to show next to unresolved discussions
    tree_type = "simple", -- Type of discussion tree - "simple" means just list of discussions, "by_file_name" means file tree with discussions under file
    toggle_tree_type = "i", -- Toggle type of discussion tree - "simple", or "by_file_name"
    winbar = nil -- Custom function to return winbar title, should return a string. Provided with WinbarTable (defined in annotations.lua)
                 -- If using lualine, please add "gitlab" to disabled file types, otherwise you will not see the winbar.
  },
  info = { -- Show additional fields in the summary view
    enabled = true,
    horizontal = false, -- Display metadata to the left of the summary rather than underneath
    fields = { -- The fields listed here will be displayed, in whatever order you choose
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
    enabled = true, -- Show diagnostics for gitlab comments in the reviewer
    skip_resolved_discussion = false, -- Show diagnostics for resolved discussions
    severity = vim.diagnostic.severity.INFO, -- ERROR, WARN, INFO, or HINT
    virtual_text = false, -- Whether to show the comment text inline as floating virtual text
    priority = 100, -- Higher will override LSP warnings, etc
    icons = {
      comment = "→|",
      range = " |",
    },
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
  merge = { -- The default behaviors when merging an MR, see "Merging an MR"
    squash = false,
    delete_branch = false,
  },
  create_mr = {
    target = nil, -- Default branch to target when creating an MR
    template_file = nil, -- Default MR template in .gitlab/merge_request_templates
    title_input = { -- Default settings for MR title input window
      width = 40,
      border = "rounded",
    },
  },
  colors = {
    discussion_tree = {
      username = "Keyword",
      date = "Comment",
      chevron = "DiffviewNonText",
      directory = "Directory",
      directory_icon = "DiffviewFolderSign",
      file_name = "Normal",
    }
  }
})
```

## Usage

First, check out the branch that you want to review locally.

```
git checkout feature-branch
```

Then open Neovim. To begin, try running the `summary` command or the `review` command.

## Keybindings

The plugin does not set up any keybindings outside of the special buffers it creates,
you need to set them up yourself. Here's what I'm using:

```lua
local gitlab = require("gitlab")
local gitlab_server = require("gitlab.server")
vim.keymap.set("n", "glr", gitlab.review)
vim.keymap.set("n", "gls", gitlab.summary)
vim.keymap.set("n", "glA", gitlab.approve)
vim.keymap.set("n", "glR", gitlab.revoke)
vim.keymap.set("n", "glc", gitlab.create_comment)
vim.keymap.set("v", "glc", gitlab.create_multiline_comment)
vim.keymap.set("v", "glC", gitlab.create_comment_suggestion)
vim.keymap.set("n", "glO", gitlab.create_mr)
vim.keymap.set("n", "glm", gitlab.move_to_discussion_tree_from_diagnostic)
vim.keymap.set("n", "gln", gitlab.create_note)
vim.keymap.set("n", "gld", gitlab.toggle_discussions)
vim.keymap.set("n", "glaa", gitlab.add_assignee)
vim.keymap.set("n", "glad", gitlab.delete_assignee)
vim.keymap.set("n", "glla", gitlab.add_label)
vim.keymap.set("n", "glld", gitlab.delete_label)
vim.keymap.set("n", "glra", gitlab.add_reviewer)
vim.keymap.set("n", "glrd", gitlab.delete_reviewer)
vim.keymap.set("n", "glp", gitlab.pipeline)
vim.keymap.set("n", "glo", gitlab.open_in_browser)
vim.keymap.set("n", "glM", gitlab.merge)
```

For more information about each of these commands, and about the APIs in general, run `:h gitlab.nvim.api`
