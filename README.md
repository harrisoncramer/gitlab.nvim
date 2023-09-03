# gitlab.nvim

This Neovim plugin is designed to make it easy to review Gitlab MRs from within the editor. This means you can do things like:

- Read and Edit an MR description
- Approve or revoke approval for an MR
- Add or remove reviewers and assignees
- Resolve, reply to, and unresolve discussion threads
- Create, edit, delete, and reply to comments on an MR

And a lot more!

https://github.com/harrisoncramer/gitlab.nvim/assets/32515581/ab5a8597-32fa-4a28-a7d2-098bae8d3d19

## Requirements

- <a href="https://go.dev/">Go >= v1.19</a>
- <a href="https://www.gnu.org/software/make/manual/make.html">make (for install)</a>
- <a href="https://github.com/dandavison/delta">delta</a>

## Quick Start

1. Install Go and Delta Dependencies
2. Add configuration (see Installation section)
3. Checkout your feature branch: `git checkout feature-branch`
4. Open Neovim
5. Run `:lua require("gitlab").review()` to open the reviewer pane, or `:lua require("gitlab").summary()` to read the MR description and get started.

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
  build = function () require("gitlab.server").build() end, -- Builds the Go binary
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
    "nvim-lua/plenary.nvim"
  },
  run = function() require("gitlab.server").build() end,
  config = function()
    require("gitlab").setup()
  end,
}
```

## Configuration

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
  port = 21036, -- The port of the Go server, which runs in the background
  log_path = vim.fn.stdpath("cache") .. "/gitlab.nvim.log", -- Log path for the Go server
  reviewer = "delta", -- The reviewer type (only delta is currently supported)
  popup = { -- The popup for comment creation, editing, and replying
    exit = "<Esc>",
    perform_action = "<leader>s", -- Once in normal mode, does action (like saving comment or editing description, etc)
    perform_linewise_action = "<leader>l", -- Once in normal mode, does whatever the linewise action is (see job logs, etc)
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

The `summary` command will pull down the MR description into a buffer so that you can read it. To edit the description, edit the buffer and press the `perform_action` keybinding when in normal mode (it's `<leader>s` by default):

```lua
require("gitlab").summary()
```

 The `review` command will open up view of all the changes that have been made in this MR compared to the target branch in a review pane. You can leave comments on the changes.

```lua
require("gitlab").review()
require("gitlab").create_comment()
```

Gitlab groups threads of comments together into "discussions." 

To display discussions for the current MR, use the `toggle_discussions()` command, which will show the discussions in a split window. 

You can jump to the comment's location the reviewer window by using the `m` key, or the actual file with the 'j' key, when hovering over the line in the tree. 

Within the discussion tree, you can delete/edit/reply to comments, or toggle them as resolved or not.

```lua
require("gitlab").toggle_discussions()
require("gitlab").delete_comment()
require("gitlab").edit_comment()
require("gitlab").reply()
require("gitlab").toggle_resolved()
```

If you'd like to create a note in an MR (like a comment, but not linked to a specific line) call the `create_note()` command. Similar commands are available on the note tree, which is visible next to the discussion tree for comments.

```lua
require("gitlab").create_note()
```

You can approve or revoke approval for an MR:

```lua
require("gitlab").approve()
require("gitlab").revoke()
```

You can view the status of the pipeline for the current MR. To re-trigger failed jobs in the pipeline manually, use your `settings.popup.perform_action` keybinding:

```lua
require("gitlab").pipeline()
```

The `add_reviewer` and `delete_reviewer` commands, as well as the `add_assignee` and `delete_assignee` functions, will let you choose from a list of users who are availble in the current project:

```lua
require("gitlab").add_reviewer()
require("gitlab").delete_reviewer()
require("gitlab").add_assignee()
require("gitlab").delete_assignee()
```

These commands use Neovim's built in picker, which is much nicer if you install <a href="https://github.com/stevearc/dressing.nvim">dressing</a>. If you use Dressing, please enable it:

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
```

## Troubleshooting

**To check that the current settings of the plugin are configured correctly, please run: `:lua require("gitlab").print_settings()`**

This plugin uses a Golang server to reach out to Gitlab. It's possible that something is going wrong when starting that server or connecting with Gitlab. The Golang server runs outside of Neovim, and can be interacted with directly in order to troubleshoot. To start the server, check out your feature branch and run these commands:

```
:lua require("gitlab.server").build()
:lua require("gitlab.server").start(function() print("Server started") end)
```

You can directly interact with the Go server like any other process:

```
curl --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" localhost:21036/info
```

This is the API call that is happening from within Neovim when you run the `summary` command.

If you are able to build and start the Go server and hit the endpoint successfully for the command you are trying to run (such as creating a comment or approving a merge request) then something is wrong with the Lua code. In that case, please file a bug report.

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
