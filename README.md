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

For a list of all these settings please run `:h gitlab.nvim.configuring-the-plugin` which will show you the help stored in [doc/gitlab.nvim.txt](doc/gitlab.nvim.txt).

## Keybindings

The plugin sets up a number of useful keybindings in the special buffers it creates, and some global keybindings as well. Refer to the relevant section of the manual `:h gitlab.nvim.keybindings` for more details.

### Or if you are using [which-key](https://github.com/folke/which-key.nvim), here's what you can use:

```lua
local wk = require("which-key")
local gitlab = require("gitlab")

wk.register({
    ["lb"] = { gitlab.choose_merge_request, "choose_merge_request" },
    ["lr"] = { gitlab.review, "review" },
    ["ls"] = { gitlab.summary, "summary" },
    ["lA"] = { gitlab.approve, "approve" },
    ["lR"] = { gitlab.revoke, "revoke" },
    ["lc"] = { gitlab.create_comment, "create_comment" },
    ["lO"] = { gitlab.create_mr, "create_mr" },
    ["lm"] = { gitlab.move_to_discussion_tree_from_diagnostic, "move_to_discussion_tree_from_diagnostic" },
    ["ln"] = { gitlab.create_note, "create_note" },
    ["ld"] = { gitlab.toggle_discussions, "toggle_discussions" },
    ["laa"] = { gitlab.add_assignee, "add_assignee" },
    ["lad"] = { gitlab.delete_assignee, "delete_assignee" },
    ["lla"] = { gitlab.add_label, "add_label" },
    ["lld"] = { gitlab.delete_label, "delete_label" },
    ["lra"] = { gitlab.add_reviewer, "add_reviewer" },
    ["lrd"] = { gitlab.delete_reviewer, "delete_reviewer" },
    ["lp"] = { gitlab.pipeline, "pipeline" },
    ["lo"] = { gitlab.open_in_browser, "open_in_browser" },
    ["lM"] = { gitlab.merge, "merge" },
    ["lu"] = { gitlab.copy_mr_url, "copy_mr_url" },
    ["lP"] = { gitlab.publish_all_drafts, "publish_all_drafts" },
    ["lD"] = { gitlab.toggle_draft_mode, "toggle_draft_mode" },
}, { prefix = "g", mode = "n" })

wk.register({
    ["lc"] = { gitlab.create_multiline_comment, "create_multiline_comment" },
    ["lC"] = { gitlab.create_comment_suggestion, "create_comment_suggestion" },
}, { prefix = "g", mode = "v" })
```

For more information about each of these commands, and about the APIs in general, run `:h gitlab.nvim.api`

## Contributing

Contributions to the plugin are welcome. Please read [.github/CONTRIBUTING.md](.github/CONTRIBUTING.md) before you start working on a pull request.
