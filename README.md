# gitlab.nvim

This Neovim plugin is designed to make it easy to review Gitlab MRs from within the editor. This means you can do things like:

- Create, edit, delete, and reply to comments on an MR
- Read and Edit an MR description
- Approve/Revoke Approval for an MR

https://github.com/harrisoncramer/gitlab.nvim/assets/32515581/dfd3aa8a-6fc4-4e43-8d2f-489df0745822

## Requirements

- <a href="https://go.dev/">Go</a>
- <a href="https://www.gnu.org/software/make/manual/make.html">make (for install)</a>
- <a href="https://github.com/MunifTanjim/nui.nvim">nui.nvim</a>
- <a href="https://github.com/nvim-lua/plenary.nvim">plenary.nvim</a>

## Installation

With <a href="https://github.com/folke/lazy.nvim">Lazy</a>:

```lua
return {
  "harrisoncramer/gitlab.nvim",
  dependencies = {
    "MunifTanjim/nui.nvim",
    "nvim-lua/plenary.nvim",
    "stevearc/dressing.nvim" -- Recommended but not required. Better UI for pickers.
    enabled = true,
  },
  build = function () require("gitlab").build() end, -- Builds the Go binary
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
  run = function() require("gitlab").build() end,
  config = function()
    require("gitlab").setup()
  end,
}
```

## Configuration

This plugin requires a `.gitlab.nvim` file in the root of the local Gitlab directory. Provide this file with values required to connect to your gitlab instance (gitlab_url is optional, use only for self-hosted instances):

```
project_id=112415
auth_token=your_gitlab_token
gitlab_url=https://my-personal-gitlab-instance.com/
```

If you don't want to write your authentication token into a dotfile, you may provide it as a shell variable. For instance in your `.bashrc` or `.zshrc` file:

```bash
export AUTH_TOKEN="your_gitlab_token"
```

By default, the plugin will interact with MRs against a "main" branch. You can configure this by passing in the `base_branch` option to the `.gitlab.nvim` configuration file for your project.

```
project_id=112415
auth_token=your_gitlab_token
gitlab_url=https://my-personal-gitlab-instance.com/
base_branch=master
```

## Configuring the Plugin


Here is the default setup function. All of these values are optional, and if you call this function with no values the defaults will be used:

```lua
require("gitlab").setup({
  port = 20136, -- The port of the Go server, which runs in the background
  log_path = vim.fn.stdpath("cache") .. "gitlab.nvim.log", -- Log path for the Go server
  keymaps = {
    popup = { -- The popup for comment creation, editing, and replying
      exit = "<Esc>",
      perform_action = "<leader>s", -- Once in normal mode, does action (like saving comment or editing description, etc)
    },
    discussion_tree = { -- The discussion tree that holds all comments
      jump_to_location = "o",
      edit_comment = "e",
      delete_comment = "dd",
      reply_to_comment = "r",
      toggle_node = "t",
      position = "left", -- "top", "right", "bottom" or "left"
      size = "20%", -- Size of split
      relative = "editor" -- Position relative to "editor" or "window"
    },
    dialogue = { -- The confirmation dialogue for deleting comments
      focus_next = { "j", "<Down>", "<Tab>" },
      focus_prev = { "k", "<Up>", "<S-Tab>" },
      close = { "<Esc>", "<C-c>" },
      submit = { "<CR>", "<Space>" },
    }
  }
})
```

## Usage

First, check out the branch that you want to review locally. 

```
git checkout feature-branch
```

Then open Neovim and the reviewer will be initialized. The `project_id` you specify in your configuration file must match the project_id of the Gitlab project your terminal is inside of. 

The `summary` command will pull down the MR description into a buffer so that you can read it. To edit the description, edit the buffer and press the `perform_action` keybinding when in normal mode (it's `<leader>s` by default):

```lua
require("gitlab").summary()
```


The `approve` command will approve the merge request for the current branch:

```lua
require("gitlab").approve()
```

The `revoke` command will revoke approval for the merge request for the current branch:

```lua
require("gitlab").revoke()
```

The `comment` command will open up a NUI popover that will allow you to create a Gitlab comment on the current line. To send the comment, use `<leader>s` while the comment popup is open:

```lua
require("gitlab").create_comment()
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

### Discussions

Gitlab groups threads of notes together into "disucssions." To get a list of all the discussions for the current MR, use the `list_discussions` command. This command will open up a split view of all the comments on the current merge request. You can jump to the comment location by using the `o` key in the tree buffer, and you can reply to a thread by using the `r` keybinding in the tree buffer:

```lua
require("gitlab").list_discussions()
```

Within the discussion tree, there are several functions that you can call, however, it's better to use the keybindings provided in the setup function. If you want to call them manually, they are:

```lua
require("gitlab").delete_comment()
require("gitlab").edit_comment()
require("gitlab").reply()
```

## Keybindings

The plugin does not set up any keybindings outside of these buffers, you need to set them up yourself. Here's what I'm using:

```lua
local gitlab = require("gitlab")
vim.keymap.set("n", "<leader>gls", gitlab.summary)
vim.keymap.set("n", "<leader>glA", gitlab.approve)
vim.keymap.set("n", "<leader>glR", gitlab.revoke)
vim.keymap.set("n", "<leader>glc", gitlab.create_comment)
vim.keymap.set("n", "<leader>gld", gitlab.list_discussions)
vim.keymap.set("n", "<leader>glaa", gitlab.add_assignee)
vim.keymap.set("n", "<leader>glad", gitlab.delete_assignee)
vim.keymap.set("n", "<leader>glra", gitlab.add_reviewer)
vim.keymap.set("n", "<leader>glrd", gitlab.delete_reviewer)
```

## Troubleshooting

This plugin uses a Golang server to reach out to Gitlab. The Golang server runs outside of Neovim, and can be interacted with directly in order to troubleshoot. The server will start up when you open Neovim with a MR branch. You can curl it directly:

```
curl --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" localhost:21036/info
```

This is the API call that is happening from within Neovim when you run the `summary` command.

This Go server, in turn, writes logs to the log path that is configured in your setup function. These are written by default to `~/.cache/nvim/gitlab.nvim.log` and will be written each time the server reaeches out to Gitlab. 

If the Golang server is not starting up correctly, please check your `.gitlab.nvim` file and your setup function. You can, however, try running the Golang server independently of Neovim. For instance, to start it up for a certain project, navigate to your plugin directory, and build the binary (these are instructions for Lazy) and move that binary to your project. You can then try running the binary directly, or even with a debugger like Delve:

```bash
$ cd ~/.local/share/nvim/lazy/gitlab.nvim
$ cd cmd
$ go build -gcflags=all="-N -l" -o bin && cp ./bin ~/path-to-your-project
$ cd ~/path-to-your-project
$ dlv exec ./bin -- 41057709 https://www.gitlab.com 21036 your-gitlab-token
```
