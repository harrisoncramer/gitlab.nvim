# gitlab.nvim

This Neovim plugin is designed to make it easy to review Gitlab MRs from within the editor. This means you can do things like:

- Read and Edit an MR description
- Approve or revoke approval for an MR
- Add or remove reviewers and assignees
- Resolve, reply to, and unresolve discussion threads
- Create, edit, delete, and reply to comments on an MR
- View and Manage Pipeline Jobs

And a lot more!

https://github.com/harrisoncramer/gitlab.nvim/assets/32515581/50f44eaf-5f99-4cb3-93e9-ed66ace0f675

## Requirements

- <a href="https://go.dev/">Go</a> >= v1.19

## Quick Start

1. Install Go
2. Install reviewer: <a href="https://github.com/dandavison/delta">delta</a> or <a href="https://github.com/sindrets/diffview.nvim">diffview</a>
3. Add configuration (see Installation section)
4. Checkout your feature branch: `git checkout feature-branch`
5. Open Neovim
6. Run `:lua require("gitlab").review()` to open the reviewer pane

## Installation

With <a href="https://github.com/folke/lazy.nvim">Lazy</a>:

```lua
return {
  "harrisoncramer/gitlab.nvim",
  dependencies = {
    "MunifTanjim/nui.nvim",
    "nvim-lua/plenary.nvim",
    "stevearc/dressing.nvim", -- Recommended but not required. Better UI for pickers.
    enabled = true,
  },
  build = function () require("gitlab.server").build(true) end, -- Builds the Go binary
  config = function()
    require("gitlab").setup() -- Uses delta reviewer by default
  end,
}
```

And with Packer:

```lua
use {
  'harrisoncramer/gitlab.nvim',
  requires = {
    "MunifTanjim/nui.nvim",
    "nvim-lua/plenary.nvim"
  },
  run = function() require("gitlab.server").build(true) end,
  config = function()
    require("gitlab").setup()
  end,
}
```

## Project Configuration

This plugin requires a `.gitlab.nvim` file in the root of the project. Provide this file with values required to connect to your gitlab instance of your repository (gitlab_url is optional, use ONLY for self-hosted instances):

```
project_id=112415
auth_token=your_gitlab_token
gitlab_url=https://my-personal-gitlab-instance.com/
```

If you don't want to write your authentication token into a dotfile, you may provide it as a shell variable. For instance in your `.bashrc` or `.zshrc` file:

```bash
export GITLAB_TOKEN="your_gitlab_token"
```

## Configuring the Plugin

Here is the default setup function. All of these values are optional, and if you call this function with no values the defaults will be used:

```lua
require("gitlab").setup({
  port = nil, -- The port of the Go server, which runs in the background, if omitted or `nil` the port will be chosen automatically
  log_path = vim.fn.stdpath("cache") .. "/gitlab.nvim.log", -- Log path for the Go server
  debug_type = "", -- "" (nothing), "request", "response", or "both" for the Go server logs
  reviewer = "delta", -- The reviewer type ("delta" or "diffview")
  attachment_dir = nil, -- The local directory for files (see the "summary" section)
  popup = { -- The popup for comment creation, editing, and replying
    exit = "<Esc>",
    perform_action = "<leader>s", -- Once in normal mode, does action (like saving comment or editing description, etc)
    perform_linewise_action = "<leader>l", -- Once in normal mode, does the linewise action (see logs for this job, etc)
},
  discussion_tree = { -- The discussion tree that holds all comments
    blacklist = {}, -- List of usernames to remove from tree (bots, CI, etc)
    jump_to_file = "o", -- Jump to comment location in file
    jump_to_reviewer = "m", -- Jump to the location in the reviewer window
    edit_comment = "e", -- Edit coment
    delete_comment = "dd", -- Delete comment
    reply = "r", -- Reply to comment
    toggle_node = "t", -- Opens or closes the discussion
    toggle_resolved = "p", -- Toggles the resolved status of the discussion
    position = "left", -- "top", "right", "bottom" or "left"
    size = "20%", -- Size of split
    relative = "editor", -- Position of tree split relative to "editor" or "window"
    resolved = '✓', -- Symbol to show next to resolved discussions
    unresolved = '✖', -- Symbol to show next to unresolved discussions
  },
  review_pane = { -- Specific settings for different reviewers
    delta = {
      added_file = "", -- The symbol to show next to added files
      modified_file = "", -- The symbol to show next to modified files
      removed_file = "", -- The symbol to show next to removed files
    }
  },
  dialogue = {  -- The confirmation dialogue for deleting comments
    focus_next = { "j", "<Down>", "<Tab>" },
    focus_prev = { "k", "<Up>", "<S-Tab>" },
    close = { "<Esc>", "<C-c>" },
    submit = { "<CR>", "<Space>" },
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
})
```

## Usage

First, check out the branch that you want to review locally.

```
git checkout feature-branch
```

Then open Neovim. The `project_id` you specify in your configuration file must match the project_id of the Gitlab project your terminal is inside of.

### Summary

The `summary` action will pull down the MR description into a buffer so that you can read it. To edit the description, use the `settings.popup.perform_action` keybinding.

```lua
require("gitlab").summary()
```

The upper part of the popup contains the title, which can also be edited and sent via the perform action keybinding in the same manner.

### Reviewing Diffs

The `review` action will open a diff of the changes. You can leave comments using the `create_comment` action.

```lua
require("gitlab").review()
require("gitlab").create_comment()
```

The reviewer is Delta by default, but you can configure the plugin to use Diffview instead.

### Discussions and Notes

Gitlab groups threads of comments together into "discussions."

To display all discussions for the current MR, use the `toggle_discussions` action, which will show the discussions in a split window.

```lua
require("gitlab").toggle_discussions()
```

You can jump to the comment's location in the reviewer window by using the `state.settings.discussion_tree.jump_to_reviewer` key, or the actual file with the 'state.settings.discussion_tree.jump_to_file' key.

Within the discussion tree, you can delete/edit/reply to comments with the `state.settings.discussion_tree.delete_comment` `state.settings.discussion_tree.edit_comment` and `state.settings.discussion_tree.reply` keys, and toggle them as resolved with the `state.settings.discussion_tree.toggle_resolved` key.

If you'd like to create a note in an MR (like a comment, but not linked to a specific line) use the `create_note` action. The same keybindings for delete/edit/reply are available on the note tree.

```lua
require("gitlab").create_note()
```

### Uploading Files

To attach a file to an MR description, reply, comment, and so forth use the `settings.popup.perform_linewise_action` keybinding when the the popup is open. This will open a picker that will look in the directory you specify in the `settings.attachment_dir` folder (this must be an absolute path) for files.

When you have picked the file, it will be added to the current buffer at the current line.

Use the `settings.popup.perform_action` to send the changes to Gitlab.

### MR Approvals

You can approve or revoke approval for an MR with the `approve` and `revoke` actions respectively.

```lua
require("gitlab").approve()
require("gitlab").revoke()
```

### Pipelines

You can view the status of the pipeline for the current MR with the `pipeline` action.

```lua
require("gitlab").pipeline()
```

To re-trigger failed jobs in the pipeline manually, use the `settings.popup.perform_action` keybinding. To open the log trace of a job in a new Neovim buffer, use your `settings.popup.perform_linewise_action` keybinding.

### Reviewers and Assignees

The `add_reviewer` and `delete_reviewer` actions, as well as the `add_assignee` and `delete_assignee` functions, will let you choose from a list of users who are availble in the current project:

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

## Keybindings

The plugin does not set up any keybindings outside of these buffers, you need to set them up yourself. Here's what I'm using:

```lua
local gitlab = require("gitlab")
vim.keymap.set("n", "<leader>glr", gitlab.review)
vim.keymap.set("n", "<leader>gls", gitlab.summary)
vim.keymap.set("n", "<leader>glA", gitlab.approve)
vim.keymap.set("n", "<leader>glR", gitlab.revoke)
vim.keymap.set("n", "<leader>glc", gitlab.create_comment)
vim.keymap.set("n", "<leader>gln", gitlab.create_note)
vim.keymap.set("n", "<leader>gld", gitlab.toggle_discussions)
vim.keymap.set("n", "<leader>glaa", gitlab.add_assignee)
vim.keymap.set("n", "<leader>glad", gitlab.delete_assignee)
vim.keymap.set("n", "<leader>glra", gitlab.add_reviewer)
vim.keymap.set("n", "<leader>glrd", gitlab.delete_reviewer)
vim.keymap.set("n", "<leader>glp", gitlab.pipeline)
vim.keymap.set("n", "<leader>glo", gitlab.open_in_browser)
```

## Troubleshooting

**To check that the current settings of the plugin are configured correctly, please run: `:lua require("gitlab").print_settings()`**

This plugin uses a Golang server to reach out to Gitlab. It's possible that something is going wrong when starting that server or connecting with Gitlab. The Golang server runs outside of Neovim, and can be interacted with directly in order to troubleshoot. To start the server, check out your feature branch and run these commands:

```
:lua require("gitlab.server").build(true)
:lua require("gitlab.server").start(function() print("Server started") end)
```

You can directly interact with the Go server like any other process:

```
curl --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" localhost:21036/info
```

This is the API call that is happening from within Neovim when you run the `summary` action.

If you are able to build and start the Go server and hit the endpoint successfully for the action you are trying to run (such as creating a comment or approving a merge request) then something is wrong with the Lua code. In that case, please file a bug report.

This Go server, in turn, writes logs to the log path that is configured in your setup function. These are written by default to `~/.cache/nvim/gitlab.nvim.log` and will be written each time the server reaeches out to Gitlab.

If the Golang server is not starting up correctly, please check your `.gitlab.nvim` file and your setup function. You can, however, try running the Golang server independently of Neovim. For instance, to start it up for a certain project, navigate to your plugin directory, and build the binary (these are instructions for Lazy) and move that binary to your project. You can then try running the binary directly, or even with a debugger like Delve:

```bash
$ cd ~/.local/share/nvim/lazy/gitlab.nvim
$ cd cmd
$ go build -gcflags=all="-N -l" -o bin && cp ./bin ~/path-to-your-project
$ cd ~/path-to-your-project
$ dlv exec ./bin -- 41057709 https://www.gitlab.com 21036 your-gitlab-token
```

## Extra Goodies

If you are like me and want to quickly switch between recent branches and recent merge request reviews and assignments, check out the git scripts contained <a href="https://github.com/harrisoncramer/.dotfiles/blob/main/scripts/bin/git-reviews">here</a> and <a href="https://github.com/harrisoncramer/.dotfiles/blob/main/scripts/bin/git-authored">here</a> for inspiration.
