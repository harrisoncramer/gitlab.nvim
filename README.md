# gitlab.nvim

NOTE: This plugin is currently a work in progress and not stable, or ready for public use.

This Neovim plugin is designed to make it easy to review Gitlab MRs from within the editor. The plugin wraps around the Gitlab CLI tool.

https://user-images.githubusercontent.com/32515581/232324922-a0796d0e-447b-463b-9eee-a42ce7e97cba.mp4

## Requirements

- Go
- The Gitlab CLI
- <a href="https://github.com/folke/lazy.nvim">lazy.nvim</a>
- <a href="https://github.com/MunifTanjim/nui.nvim">nui.nvim</a>
- <a href="https://github.com/rcarriga/nvim-notify">nvim-notify</a>
- <a href="https://github.com/sindrets/diffview.nvim">diffview.nvim</a>

## Installation

First, configure the Gitlab CLI. Next, you'll need to have the following environment variable available in your shell:

```bash
export GITLAB_TOKEN="your_gitlab_token"
```

Then install the plugin with <a href="https://github.com/folke/lazy.nvim">Lazy</a>:

```lua
return {
  "harrisoncramer/gitlab",
  dependencies = {
    "sindrets/diffview.nvim",
    "rcarriga/nvim-notify",
    "MunifTanjim/nui.nvim"
  },
  config = function()
    local gitlab = require("gitlab")
    gitlab.setup({ project_id = 3 })
  end,
}
```

By default, the tool will look for and interact with MRs against a "main" branch. You can configure this by passing in the `base_branch` option:

```lua
require('gitlab_nvim').setup({ project_id = 3, base_branch = 'master' })
```

The first time you call the setup function the Go binary will be built.

## Usage

First, check out the branch that you want to review locally.


The `summary` command will pull down the MR description into a buffer so that you can read it

```lua
require("gitlab_nvim").summary()
```

The `review` command will open up a diffview of all your changed files, using the diffview plugin

```lua
require("gitlab_nvim").review()
```

The `approve` command will approve the merge request for the current branch

```lua
require("gitlab_nvim").approve()
```

The `revoke` command will revoke approval for the merge request for the current branch.

```lua
require("gitlab_nvim").revoke()
```

The `comment` command will open up a NUI popover that will allow you to create a Gitlab comment on the current line. To send the comment, use `<leader>s`

```lua
require("gitlab_nvim").comment()
```

## Keybindings

This plugin does not create any keybindings by default, _except_ for inside of the popups, where:

- `<esc>` quits the popups
- `<leader>s` sends the comment

These bindings are local and do not overwrite anything in your configuration.

These are the keybindings that I'm using:

```lua
local gitlab = require("gitlab")
vim.keymap.set("n", "<leader>gls", gitlab.summary)
vim.keymap.set("n", "<leader>glr", gitlab.review)
vim.keymap.set("n", "<leader>gla", gitlab.approve)
vim.keymap.set("n", "<leader>glR", gitlab.revoke)
vim.keymap.set("n", "<leader>glc", gitlab.comment)
```
