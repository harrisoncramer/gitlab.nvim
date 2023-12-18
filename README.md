# gitlab.nvim

This Neovim plugin is designed to make it easy to review Gitlab MRs from within the editor. This means you can do things like:

- Create, approve, and merge MRs for the current branch
- Read and edit an MR description
- Add or remove reviewers and assignees
- Resolve, reply to, and unresolve discussion threads
- Create, edit, delete, and reply to comments
- View and manage pipeline Jobs
- Upload files, jump to the browser, and a lot more!

https://github.com/harrisoncramer/gitlab.nvim/assets/32515581/dc5c07de-4ae6-4335-afe1-d554e3804372

## Table of Contents

- [Requirements](#requirements)
- [Quick Start](#quick-start)
- [Installation](#installation)
- [Connecting to Gitlab](#connecting-to-gitlab)
- [Configuring the Plugin](#configuring-the-plugin)
- [Usage](#usage)
  - [The Summary view](#the-summary-view)
  - [Reviewing an MR](#reviewing-an-mr)
  - [Merging](#merging-an-mr)
  - [Discussions and Notes](#discussions-and-notes)
  - [Signs and Diagnostics](#signs-and-diagnostics)
  - [Uploading Files](#uploading-files)
  - [Approvals](#mr-approvals)
  - [Creating an MR](#creating-an-mr)
  - [Pipelines](#pipelines)
  - [Reviewers and Assignees](#reviewers-and-assignees)
  - [Restarting or Shutting down](#restarting-or-shutting-down)
- [Keybindings](#keybindings)
- [Troubleshooting](#troubleshooting)

## Requirements

- <a href="https://go.dev/">Go</a> >= v1.19

## Quick Start

1. Install Go
2. Add configuration (see Installation section)
3. Checkout your feature branch: `git checkout feature-branch`
4. Open Neovim
5. Run `:lua require("gitlab").review()` to open the reviewer pane

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

## Configuring the Plugin

Here is the default setup function. All of these values are optional, and if you call this function with no values the defaults will be used:

```lua
require("gitlab").setup({
  port = nil, -- The port of the Go server, which runs in the background, if omitted or `nil` the port will be chosen automatically
  log_path = vim.fn.stdpath("cache") .. "/gitlab.nvim.log", -- Log path for the Go server
  config_path = nil, -- Custom path for `.gitlab.nvim` file, please read the "Connecting to Gitlab" section
  debug = { go_request = false, go_response = false }, -- Which values to log
  attachment_dir = nil, -- The local directory for files (see the "summary" section)
  help = "?", -- Opens a help popup for local keymaps when a relevant view is focused (popup, discussion panel, etc)
  popup = { -- The popup for comment creation, editing, and replying
    exit = "<Esc>",
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
    switch_view = "T", -- Toggles between the notes and discussions views
    default_view = "discussions" -- Show "discussions" or "notes" by default
    blacklist = {}, -- List of usernames to remove from tree (bots, CI, etc)
    jump_to_file = "o", -- Jump to comment location in file
    jump_to_reviewer = "m", -- Jump to the location in the reviewer window
    edit_comment = "e", -- Edit comment
    delete_comment = "dd", -- Delete comment
    reply = "r", -- Reply to comment
    toggle_node = "t", -- Opens or closes the discussion
    toggle_resolved = "p" -- Toggles the resolved status of the whole discussion
    position = "left", -- "top", "right", "bottom" or "left"
    open_in_browser = "b" -- Jump to the URL of the current note/discussion
    size = "20%", -- Size of split
    relative = "editor", -- Position of tree split relative to "editor" or "window"
    resolved = '✓', -- Symbol to show next to resolved discussions
    unresolved = '-', -- Symbol to show next to unresolved discussions
    tree_type = "simple", -- Type of discussion tree - "simple" means just list of discussions, "by_file_name" means file tree with discussions under file
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
      "branch",
      "pipeline",
    },
  },
  discussion_sign_and_diagnostic = {
    skip_resolved_discussion = false,
    skip_old_revision_discussion = true,
  },
  discussion_sign = {
    -- See :h sign_define for details about sign configuration.
    enabled = true,
    text = "💬",
    linehl = nil,
    texthl = nil,
    culhl = nil,
    numhl = nil,
    priority = 20, -- Priority of sign, the lower the number the higher the priority
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
    display_opts = {}, -- see opts in vim.diagnostic.set
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

### The Summary view

The `summary` action will open the MR title and description.

```lua
require("gitlab").summary()
```

After editing the description or title, you may save your changes via the `settings.popup.perform_action` keybinding.

By default this plugin will also show additional metadata about the MR in a separate pane underneath the description. This can be disabled, and these fields can be reordered or removed. Please see the `settings.info` section of the configuration.

### Reviewing an MR

The `review` action will open a diff of the changes. You can leave comments using the `create_comment` action. In visual mode, add multiline comments with the `create_multiline_comment` command, and add suggested changes with the `create_comment_suggestion` command.

```lua
require("gitlab").review()
require("gitlab").create_comment()
require("gitlab").create_multiline_comment()
require("gitlab").create_comment_suggestion()
```

For suggesting changes you can use `create_comment_suggestion` in visual mode which works similar to `create_multiline_comment` but prefills the comment window with Gitlab's [suggest changes](https://docs.gitlab.com/ee/user/project/merge_requests/reviews/suggestions.html) code block with prefilled code from the visual selection.

### Discussions and Notes

Gitlab groups threads of comments together into "discussions."

To display all discussions for the current MR, use the `toggle_discussions` action, which will show the discussions in a split window.

```lua
require("gitlab").toggle_discussions()
```

You can jump to the comment's location in the reviewer window by using the `state.settings.discussion_tree.jump_to_reviewer` key, or to the actual file with the `state.settings.discussion_tree.jump_to_file` key.

Within the discussion tree, you can delete/edit/reply to comments with the `state.settings.discussion_tree.SOME_ACTION` keybindings.

If you'd like to create a note in an MR (like a comment, but not linked to a specific line) use the `create_note` action. The same keybindings for delete/edit/reply are available on the note tree.

```lua
require("gitlab").create_note()
```

### Signs and diagnostics

By default when reviewing files you will see signs and diagnostics (if enabled in configuration). When cursor is on diagnostic line you can view discussion thread by using `vim.diagnostic.show`. You can also jump to discussion tree where you can reply, edit or delete discussion.

```lua
require("gitlab").move_to_discussion_tree_from_diagnostic()
```

The `discussion_sign` configuration controls the display of signs for discussions in the reviewer pane. This allows users to jump to comments in the current buffer in the reviewer pane directly. Keep in mind that the highlights provided here can be overridden by other highlights (for example from `diffview.nvim`). 

These diagnostics are configurable in the same way that diagnostics are typically configurable in Neovim. For instance, the `severity` key sets the diagnostic severity level and should be set to one of `vim.diagnostic.severity.ERROR`, `vim.diagnostic.severity.WARN`, `vim.diagnostic.severity.INFO`, or `vim.diagnostic.severity.HINT`. The `display_opts` option configures the diagnostic display options (this is directly used as opts in vim.diagnostic.set). Here you can configure values like:

- `virtual_text` - Show virtual text for diagnostics.
- `underline` - Underline text for diagnostics.

Diagnostics for discussions use the `gitlab_discussion` namespace. See `:h vim.diagnostic.config` and `:h diagnostic-structure` for more details. Signs and diagnostics have common settings in `discussion_sign_and_diagnostic`. This allows customizing if discussions that are resolved or no longer relevant should still display visual indicators in the editor. The `skip_resolved_discussion` Boolean will control visibility of resolved discussions, and `skip_old_revision_discussion` whether to show signs and diagnostics for discussions on outdated diff revisions.

When interacting with multiline comments, the cursor must be on the "main" line of diagnostic, where the `discussion_sign.text` is shown, otherwise `vim.diagnostic.show` and `jump_to_discussion_tree_from_diagnostic` will not work.

### Uploading Files

To attach a file to an MR description, reply, comment, and so forth use the `settings.popup.perform_linewise_action` keybinding when the popup is open. This will open a picker that will look for files in the directory you specify in the `settings.attachment_dir` folder (this must be an absolute path).

When you have picked the file, it will be added to the current buffer at the current line.

Use the `settings.popup.perform_action` to send the changes to Gitlab.

### MR Approvals

You can approve or revoke approval for an MR with the `approve` and `revoke` actions respectively.

```lua
require("gitlab").approve()
require("gitlab").revoke()
```

### Merging an MR

The `merge` action will merge an MR. The MR must be in a "mergeable" state for this command to work.

```lua
require("gitlab").merge()
require("gitlab").merge({ squash = false, delete_branch = false })
```

You can configure default behaviors via the setup function, values passed into the `merge` action will override the defaults.

If you enable `squash` you will be prompted for a squash message. To use the default message, leave the popup empty. Use the `settings.popup.perform_action` to merge the MR with your message.


### Creating an MR

To create an MR for the current branch, make sure you have the branch checked out. Then, use the `create_mr` action.

```lua
require("gitlab").create_mr()
require("gitlab").create_mr({ target = "main" })
require("gitlab").create_mr({ target = "main", template_file = "my-template.md" })
```

You can configure default behaviors via the setup function, values passed into the `create_mr` action will override your defaults.

### Pipelines

You can view the status of the pipeline for the current MR with the `pipeline` action.

```lua
require("gitlab").pipeline()
```

To re-trigger failed jobs in the pipeline manually, use the `settings.popup.perform_action` keybinding. To open the log trace of a job in a new Neovim buffer, use your `settings.popup.perform_linewise_action` keybinding.

### Reviewers and Assignees

The `add_reviewer` and `delete_reviewer` actions, as well as the `add_assignee` and `delete_assignee` functions, will let you choose from a list of users who are available in the current project:

```lua
require("gitlab").add_reviewer()
require("gitlab").delete_reviewer()
require("gitlab").add_assignee()
require("gitlab").delete_assignee()
```

These actions use Neovim's built in picker, which is much nicer if you install <a href="https://github.com/stevearc/dressing.nvim">dressing</a>. If you use Dressing, please enable it:

```lua
require("dressing").setup({
    input = {
        enabled = true
    }
})
```

### Restarting or Shutting Down

The `gitlab.nvim` server will shut down automatically when you exit Neovim. However, if you would like to manage this yourself (for instance, restart the server when you check out a new branch) you may do so via the `restart` command, or `shutdown` commands, which both accept callbacks.

```lua
require("gitlab.server").restart()
```

For instance you could set up the following keybinding to close and reopen the reviewer when checking out a new branch:

```lua
local gitlab = require("gitlab")
vim.keymap.set("n", "glB", function ()
    require("gitlab.server").restart(function () 
        vim.cmd.tabclose()
        gitlab.review() -- Reopen the reviewer after the server restarts
    end)
end)
```

## Keybindings

The plugin does not set up any keybindings outside of the special buffers it creates,
you need to set them up yourself.
Here's what I'm using (note that the `<leader>` prefix is not necessary,
as `gl` does not have a special meaning in normal mode):

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
vim.keymap.set("n", "glra", gitlab.add_reviewer)
vim.keymap.set("n", "glrd", gitlab.delete_reviewer)
vim.keymap.set("n", "glp", gitlab.pipeline)
vim.keymap.set("n", "glo", gitlab.open_in_browser)
vim.keymap.set("n", "glM", gitlab.merge)
```

## Troubleshooting

**To check that the current settings of the plugin are configured correctly, please run: `:lua require("gitlab").print_settings()`**

This plugin uses a Go server to reach out to Gitlab. It's possible that something is going wrong when starting that server or connecting with Gitlab. The Go server runs outside of Neovim, and can be interacted with directly in order to troubleshoot. To start the server, check out your feature branch and run these commands:

```lua
:lua require("gitlab.server").build(true)
:lua require("gitlab.server").start(function() print("Server started") end)
```

The easiest way to debug what's going wrong is to turn on the `debug` options in your setup function. This will allow you to see requests leaving the Go server, and the responses coming back from Gitlab. Once the server is running, you can also interact with the Go server like any other process:

```
curl --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" localhost:21036/mr/info
```
