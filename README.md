# gitlab.nvim

NOTE: THIS PROJECT IS NOT READY FOR PUBLIC CONSUMPTION AND IS STILL UNDER DEVELOPMENT.

This Neovim plugin is designed to make it easy to review Gitlab MRs from within the editor. This means you can do things like:

- Create, edit, and delete comments on an MR
- Reply to exisiting comments
- Read MR summaries
- Approve an MR
- Revoke approval for an MR

https://user-images.githubusercontent.com/32515581/233739969-216dad6e-fa77-417f-9d2d-5e875ab2fb40.mp4

## Requirements

- Go
- <a href="https://github.com/MunifTanjim/nui.nvim">nui.nvim</a>
- <a href="https://github.com/rcarriga/nvim-notify">nvim-notify</a>
- <a href="https://github.com/nvim-lua/plenary.nvim">plenary.nvim</a>

## Installation

You'll need to have an environment variable available in your shell that you use to authenticate with Gitlab's API. It should look like this:

```bash
export GITLAB_TOKEN="your_gitlab_token"
```

Then install the plugin. Here's what it looks like with <a href="https://github.com/folke/lazy.nvim">Lazy</a>:

```lua
return {
  "harrisoncramer/gitlab.nvim",
  dependencies = {
    "rcarriga/nvim-notify",
    "MunifTanjim/nui.nvim",
    "nvim-lua/plenary.nvim"
  },
  build = function () require("gitlab").build() end, -- Builds the Go binary
  config = function()
    vim.opt.termguicolors = true -- This is required if you aren't already initializing notify
    require("notify").setup({ background_colour = "#000000" })  -- This is required if you aren't already initializing notify
    require("gitlab").setup({ project_id = 3 }) -- This can be found under the project details section of your Gitlab repository.
  end,
}
```

And with Packer:

```lua
use {
  'harrisoncramer/gitlab.nvim',
  requires = {
    "rcarriga/nvim-notify",
    "MunifTanjim/nui.nvim",
    "nvim-lua/plenary.nvim"
  },
  run = function() require("gitlab").build() end,
  config = function()
    vim.opt.termguicolors = true -- This is required if you aren't already initializing notify
    require("notify").setup({ background_colour = "#000000" })  -- This is required if you aren't already initializing notify
    require("gitlab").setup({ project_id = 3 }) -- This can be found under the project details section of your Gitlab repository.
  end,
}
```

## Multiple Gitlab Repositories

By default, the tool will look for and interact with MRs against a "main" branch. You can configure this by passing in the `base_branch` option:

```lua
require('gitlab').setup({ project_id = 3, base_branch = 'master' })
```

By default, the plugin will read the `project_id` provided in the setup call. However, if you add a `.gitlab.nvim` file to the root of your directory, the plugin will read that and use it as the project_id instead. The file should only contain the ID of the project:

```
112415
```

Which is effectively like calling the setup function like this:

```lua
require('gitlab').setup({ project_id = 112415, base_branch = 'master' })
```

## Usage

First, check out the branch that you want to review locally. Then open Neovim and the reviewer will be initialized. The `project_id` you specify in your configuration must match the project_id of the Gitlab project your terminal is inside of.

The `summary` command will pull down the MR description into a buffer so that you can read it:

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
require("gitlab").comment()
```

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

This plugin does not create any keybindings outside of the plugin-specific buffers by default. These are the default keybindings in those plugin buffers:

```lua
{
  popup = { -- The popup for comment creation, editing, and replying
    exit = "<Esc>",
    perform_action = "<leader>s", -- Once in normal mode, does action
  },
  discussion_tree = { -- The discussion tree that holds all comments
    jump_to_location = "o",
    edit_comment = "e",
    delete_comment = "dd",
    reply_to_comment = "r",
    toggle_node = "t",
  },
  dialogue = { -- The confirmation dialogue for deleting comments
    focus_next = { "j", "<Down>", "<Tab>" },
    focus_prev = { "k", "<Up>", "<S-Tab>" },
    close = { "<Esc>", "<C-c>" },
    submit = { "<CR>", "<Space>" },
  }
}
```

To override the defaults, pass a keymaps table into the setup function with any keybindings you'd like to change:

```lua
local gitlab = require("gitlab")
gitlab.setup({
  project_id = 36091024,
  keymaps = {
    popup = {
      exit = "q"
    },
    discussion_tree = {
      reply_to_comment = "<leader>r"
    }
  }
})
```

The plugin does not set up any keybindings outside of these buffers, you need to set them up yourself. Here's what I'm using:

```lua
local gitlab = require("gitlab")
vim.keymap.set("n", "<leader>gls", gitlab.summary)
vim.keymap.set("n", "<leader>glA", gitlab.approve)
vim.keymap.set("n", "<leader>glR", gitlab.revoke)
vim.keymap.set("n", "<leader>glc", gitlab.create_comment)
vim.keymap.set("n", "<leader>gld", gitlab.list_discussions)
```

## Diff Views

This plugin does not provide you with a diff view out of the box for viewing changes. That is already handled by other plugins. I highly recommend using Diffview to see which files have changed in an MR. This is the function that I'm using to accomplish this:

```lua
-- Review changes against develop (will break if no develop branch present)
vim.keymap.set("n", "<leader>gR", function()
  local isDiff = vim.fn.getwinvar(nil, "&diff")
  local bufName = vim.api.nvim_buf_get_name(0)
  if isDiff ~= 0 or u.string_starts(bufName, "diff") then
    vim.cmd.tabclose()
    vim.cmd.tabprev()
  else
    vim.cmd.DiffviewOpen("main")
  end
end)
```

Which looks like this in my editor:

<img width="1727" alt="Screenshot 2023-04-21 at 6 37 39 PM" src="https://user-images.githubusercontent.com/32515581/233744560-0d718c92-f810-4fde-b40d-8b6f42eb6f0e.png">

This is useful if you plan to leave comments on the diff, because this plugin currently only supports leaving comments on lines that have been added or modified. I'm currenly working on adding functionality to allow users to leave comments on any lines, including those that have been deleted or untouched.
