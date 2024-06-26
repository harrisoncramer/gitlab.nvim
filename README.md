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
5. Run `:lua require("gitlab").choose_merge_request()`

This will checkout the branch locally, and open the plugin's reviewer pane.

NOTE: At the moment, the plugin assumes that the remote where you want to merge your feature branch
is called "origin".

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
    "harrisoncramer/gitlab.nvim",
    requires = {
      "MunifTanjim/nui.nvim",
      "nvim-lua/plenary.nvim",
      "sindrets/diffview.nvim"
      "stevearc/dressing.nvim", -- Recommended but not required. Better UI for pickers.
      "nvim-tree/nvim-web-devicons", -- Recommended but not required. Icons in discussion tree.
    },
    build = function()
      require("gitlab.server").build()
    end,
    branch = "develop",
    config = function()
      require("diffview") -- We require some global state from diffview
      local gitlab = require("gitlab")
      gitlab.setup()
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

In case even more control over the auth config is needed, there is the possibility to override the `auth_provider` settings field. It should be
a function that returns the `token` as well as the `gitlab_url` value, and a nilable error. If the `gitlab_url` is `nil`, `https://gitlab.com` is used as default.

Here an example how to use a custom `auth_provider`:
```lua
require("gitlab").setup({
  auth_provider = function()
    return "my_token", "https://custom.gitlab.instance.url", nil
  end,
}
```

For more settings, please see `:h gitlab.nvim.connecting-to-gitlab`

## Configuring the Plugin

The plugin expects you to call `setup()` and pass in a table of options. All of these values are optional, and if you call this function with no values the defaults will be used.

For a list of all these settings please run `:h gitlab.nvim` which is stored in `doc/gitlab.nvim.txt`

## Keybindings

The plugin does not set up any keybindings outside of the special buffers it creates,
you need to set them up yourself. Here's what I'm using:

```lua
local gitlab = require("gitlab")
local gitlab_server = require("gitlab.server")
vim.keymap.set("n", "glb", gitlab.choose_merge_request)
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
vim.keymap.set("n", "glu", gitlab.copy_mr_url)
vim.keymap.set("n", "glP", gitlab.publish_all_drafts)
vim.keymap.set("n", "glD", gitlab.toggle_draft_mode)
```

For more information about each of these commands, and about the APIs in general, run `:h gitlab.nvim.api`
