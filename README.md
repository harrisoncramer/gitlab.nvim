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

With Lazy:

```lua
{
    "harrisoncramer/gitlab.nvim",
    dependencies = {
      "rcarriga/nvim-notify",
      "MunifTanjim/nui.nvim",
      "sindrets/diffview.nvim"
    },
    config = function()
      require('gitlab_nvim').setup({ project_id = 3 })
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
