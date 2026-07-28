# gitlab.nvim

This Neovim plugin is designed to make it easy to review Gitlab MRs from within the editor. This means you can do things like:

- Create, approve, rebase, and merge MRs for the current branch
- Read and edit an MR description
- Add or remove reviewers and assignees
- Resolve, reply to, and unresolve discussion threads
- Create, edit, delete, and reply to comments
- View and manage pipeline Jobs
- Upload files, jump to the browser, and a lot more!

![Screenshot 2024-12-08 at 5 43 53 PM](https://github.com/user-attachments/assets/cb9e94e3-3817-4846-ba44-16ec06ea7654)

https://github.com/harrisoncramer/gitlab.nvim/assets/32515581/dc5c07de-4ae6-4335-afe1-d554e3804372

To view the help docs run `:h gitlab.nvim`.

## Requirements

- <a href="https://neovim.io">Neovim</a> >= v0.10
- <a href="https://go.dev">Go</a> >= v1.25.1, or a compatible pre-built `gitlab.nvim` [local Go server](#local-go-server) binary
- <a href="https://git-scm.com">Git</a>
- <a href="https://curl.se">Curl</a>
- <a href="https://man.cat-v.org/unix-1st/1/cat">Cat</a> (for displaying pipeline logs)

## Quick Start

1. Install the required dependencies and the plugin (see the [Installation](#installation) section)
2. Set up [connecting to Gitlab](#connecting-to-gitlab)
3. Open Neovim
4. Run `:lua require("gitlab").choose_merge_request()` or `:lua require("gitlab").review()` if already in review branch/worktree.

This will checkout the branch locally, and open the plugin's reviewer pane. Type `g?` in any of the plugin's windows to get help on context-specific keybindings. Read `:h gitlab.nvim.usage` for more information of what can be done with the plugin.

For more detailed information about the Lua APIs run `:h gitlab.nvim.api`

## Installation

With [vim.pack](https://neovim.io/doc/user/helptag.html?tag=vim.pack) (the built-in plugin
manager on Neovim 0.12 and newer):
```lua
vim.pack.add({
  "https://github.com/MunifTanjim/nui.nvim",
  "https://github.com/dlyongemallo/diffview-plus.nvim",  -- Maintained fork of "sindrets/diffview.nvim".
  "https://github.com/stevearc/dressing.nvim",      -- Recommended but not required. Better UI for pickers.
  "https://github.com/nvim-tree/nvim-web-devicons", -- Recommended but not required. Icons in discussion tree.
  "https://github.com/harrisoncramer/gitlab.nvim",
})
---@type GitlabSettings
local opts = {} -- Your configuration
require("gitlab").setup(opts)
```

With [folke/lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "harrisoncramer/gitlab.nvim",
  -- branch = "main", -- Uncomment to use a stable version. The default, possibly unstable, but more actively maintained branch is `develop`.
  dependencies = {
    "MunifTanjim/nui.nvim",
    "dlyongemallo/diffview-plus.nvim", -- Maintained fork of "sindrets/diffview.nvim".
    "stevearc/dressing.nvim", -- Recommended but not required. Better UI for pickers.
    "nvim-tree/nvim-web-devicons", -- Recommended but not required. Icons in discussion tree.
  },
  ---@type GitlabSettings
  opts = {}, -- Your configuration
}
```

And with <a href="https://github.com/lewis6991/pckr.nvim">pckr.nvim</a>:

```lua
{
  "harrisoncramer/gitlab.nvim",
  -- branch = "main", -- Uncomment to use a stable version. The default, possibly unstable, but more actively maintained branch is `develop`.
  requires = {
    "MunifTanjim/nui.nvim",
    "dlyongemallo/diffview-plus.nvim", -- Maintained fork of "sindrets/diffview.nvim".
    "stevearc/dressing.nvim", -- Recommended but not required. Better UI for pickers.
    "nvim-tree/nvim-web-devicons", -- Recommended but not required. Icons in discussion tree.
  },
  config = function()
    ---@type GitlabSettings
    local opts = {} -- Your configuration
    require("gitlab").setup(opts)
  end,
}
```

### Notes on dependencies

`gitlab.nvim` uses the `diffview.nvim` plugin for showing the diffs in a MR. We recommend using `dlyongemallo`'s [diffview+](https://github.com/dlyongemallo/diffview-plus.nvim) fork which is an actively maintained version of the plugin with many fixes and improvements (e.g., marking files as viewed). Importantly, it allows setting the same similarity threshold for detecting renamed files as is used by Gitlab (30%). When using the original [sindrets/diffview.nvim](https://github.com/sindrets/diffview.nvim) plugin, file renames may not be detected correctly and comments created on such files will contain incorrect metadata or may fail. Nevertheless, the original `sindrets/diffview.nvim` plugin will be supported by `gitlab.nvim` as long as the maintenance remains feasible.

Some plugin actions use Neovim’s `vim.ui.select()` picker, which looks much nicer if you use `dressing.nvim` or a similar UI plugin. To use Dressing with `gitlab.nvim`, enable it for `vim.ui.select()` like this:
```lua
require("dressing").setup({
  select = {
    enabled = true
  }
})
```

## Configuring the plugin

The plugin expects you to call `require("gitlab").setup(opts)` and pass in a table of options. All of these values are optional, and if you call this function with no opts table the defaults will be used.

For a list of all these settings run `:h gitlab.nvim.configuring-the-plugin` which will show you the help stored in [doc/gitlab.nvim.txt](doc/gitlab.nvim.txt).

## Local Go server

This plugin uses a local Go server to reach out to Gitlab. If you have an appropriate Go version available on your system, you can have the server built automatically. This is performed whenever the Go server binary is not found in the expected location or when the plugin is updated to a newer version.

If you can't or don't want to install Go, you can instead pre-build the server binary (some people use Nix for this) and configure `gitlab.nvim` to use that binary instead, see the `server` section in `:h gitlab.nvim.configuring-the-plugin`.

## Connecting to Gitlab

This plugin requires an <a href="https://docs.gitlab.com/ee/user/profile/personal_access_tokens.html#create-a-personal-access-token">auth token</a> to connect to Gitlab. The token can be set in the root directory of the project in a `.gitlab.nvim` environment file, or can be set via a shell environment variable called `GITLAB_TOKEN` instead. If both are present, the `.gitlab.nvim` file will take precedence.

Optionally provide a GITLAB_URL environment variable (or gitlab_url value in the `.gitlab.nvim` file) to connect to a self-hosted Gitlab instance. This is optional, use ONLY for self-hosted instances. Here's what they'd look like as environment variables:

```bash
export GITLAB_TOKEN="your_gitlab_token"
export GITLAB_URL="https://my-personal-gitlab-instance.com/"
```

And as a `.gitlab.nvim` file:

```bash
auth_token=your_gitlab_token
gitlab_url=https://my-personal-gitlab-instance.com/
```

The plugin will look for the `.gitlab.nvim` file in the root of the current project by default. However, you may provide a custom path to the configuration file via the `config_path` option. This must be an absolute path to the directory that holds your `.gitlab.nvim` file.

In case even more control over the auth config is needed, there is the possibility to override the `auth_provider` settings field. It should be a function that returns the `token` as well as the `gitlab_url` value, and a nilable error. If the `gitlab_url` is `nil`, `https://gitlab.com` is used as default.

Here an example how to use a custom `auth_provider`:
```lua
require("gitlab").setup({
  auth_provider = function()
    return "my_token", "https://custom.gitlab.instance.url", nil
  end,
}
```

For more settings, see `:h gitlab.nvim.connecting-to-gitlab`

## Keybindings

The plugin sets up a number of useful keybindings in the special buffers it creates, and some global keybindings as well. Refer to the relevant section of the manual `:h gitlab.nvim.keybindings` for more details.

For more information about each of these commands, and about the APIs in general, run `:h gitlab.nvim.api`

`gitlab.nvim` comes with a set of default `keymaps` for different contexts. You can override any of these in your configuration.

### Global Keymaps

These keymaps are available globally (i.e., in any buffer).

| Keys      | Action                                                                                            |
| --------- | ------------------------------------------------------------------------------------------------- |
| `g?`      | Open a help popup for local keymaps                                                               |
| `glaa`    | Add assignee                                                                                      |
| `glad`    | Delete assignee                                                                                   |
| `glla`    | Add label                                                                                         |
| `glld`    | Delete label                                                                                      |
| `glra`    | Add reviewer                                                                                      |
| `glrd`    | Delete reviewer                                                                                   |
| `glA`     | Approve MR                                                                                        |
| `glR`     | Revoke MR approval                                                                                |
| `glM`     | Merge the feature branch to the target branch and close MR                                        |
| `glm`     | Set MR to merge automatically when the pipeline succeeds                                          |
| `glrr`    | Rebase the feature branch of the MR on the server (if not already rebased) and pull the new state |
| `glrs`    | Same as `glrr`, but skip the CI pipeline                                                          |
| `glrf`    | Same as `glrr`, but rebase even if MR already is rebased                                          |
| `glC`     | Create a new MR for currently checked-out feature branch                                          |
| `glc`     | Chose MR for review                                                                               |
| `glS`     | Start review for the currently checked-out branch                                                 |
| `glh`     | Browse the MR's commit history, one commit at a time (read-only)                                  |
| `gl<C-R>` | Load new MR state from Gitlab and apply new diff refs to the diff view                            |
| `gls`     | Show the editable summary of the MR                                                               |
| `glu`     | Copy the URL of the MR to the system clipboard                                                    |
| `glo`     | Open the URL of the MR in the default Internet browser                                            |
| `gln`     | Create a note (comment not linked to a specific line)                                             |
| `glp`     | Show the pipeline status                                                                          |
| `gld`     | Toggle the discussions window                                                                     |
| `glD`     | Toggle between draft mode and live mode                                                           |
| `glP`     | Publish all draft comments/notes                                                                  |

#### Popup Keymaps

These `keymaps` are active in the popup windows (e.g., for creating comments, editing the summary, etc.).

| Keys      | Action                              |
| --------- | ----------------------------------- |
| `<Tab>`  | Cycle to the next field             |
| `<S-Tab>` | Cycle to the previous field         |
| `ZZ`      | Perform action (e.g., save comment) |
| `ZA`      | Perform linewise action             |
| `ZQ`      | Discard changes and quit the popup  |

#### Discussion Tree Keymaps

These `keymaps` are active in the discussion tree window.

| Keys        | Action                                                                                |
| ----------- | ------------------------------------------------------------------------------------- |
| `Ea`        | Add an emoji to the note/comment                                                      |
| `Ed`        | Remove an emoji from a note/comment                                                   |
| `dd`        | Delete comment                                                                        |
| `e`         | Edit comment                                                                          |
| `r`         | Reply to comment                                                                      |
| `-`         | Toggle the resolved status of the whole discussion                                    |
| `o`         | Jump to comment location in file                                                      |
| `a`         | Jump to the comment location in the reviewer window                                   |
| `b`         | Jump to the URL of the current note/discussion                                        |
| `u`         | Copy the URL of the current node to clipboard                                         |
| `c`         | Toggle between the notes and discussions views                                        |
| `i`         | Toggle type of discussion tree                                                        |
| `P`         | Publish the currently focused note/comment                                            |
| `dt`        | Toggle between date formats                                                           |
| `D`         | Toggle between draft mode and live mode                                               |
| `st`        | Toggle whether discussions are sorted by the "latest_reply", or by "original_comment" |
| `t`         | Open or close the discussion                                                          |
| `T`         | Open or close separately both resolved and unresolved discussions                     |
| `R`         | Open or close all resolved discussions                                                |
| `U`         | Open or close all unresolved discussions                                              |
| `<C-R>`     | Refresh the data in the view                                                          |
| `<leader>p` | Print the current node (for debugging)                                                |

#### Reviewer Keymaps

These `keymaps` are active in the reviewer window (the diff view).

| Keys | Action                                                                   |
| ---- | ------------------------------------------------------------------------ |
| `c`  | Create a comment for the lines that the following {motion} moves over    |
| `s`  | Create a suggestion for the lines that the following {motion} moves over |
| `a`  | Jump to the comment in the discussion tree                               |

## Contributing

Contributions to the plugin are welcome. Please read [.github/CONTRIBUTING.md](.github/CONTRIBUTING.md) before you start working on a pull request.
