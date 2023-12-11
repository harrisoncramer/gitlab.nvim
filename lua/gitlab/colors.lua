local state = require("gitlab.state")
local u = require("gitlab.utils")

local colors = state.settings.colors
local discussion = colors.discussion_tree

-- These variables are picked up by after/syntax/gitlab.vim
vim.g.gitlab_resolved = state.settings.discussion_tree.resolved
vim.g.gitlab_unresolved = state.settings.discussion_tree.unresolved

vim.api.nvim_set_hl(0, "GitlabUsername", u.get_colors_for_group(discussion.username))
vim.api.nvim_set_hl(0, "GitlabDate", u.get_colors_for_group(discussion.date))
vim.api.nvim_set_hl(0, "GitlabChevron", u.get_colors_for_group(discussion.chevron))
vim.api.nvim_set_hl(0, "GitlabDirectory", u.get_colors_for_group(discussion.directory))
vim.api.nvim_set_hl(0, "GitlabDirectoryIcon", u.get_colors_for_group(discussion.directory_icon))
vim.api.nvim_set_hl(0, "GitlabFileName", u.get_colors_for_group(discussion.file_name))
vim.api.nvim_set_hl(0, "GitlabResolved", u.get_colors_for_group(discussion.resolved))
vim.api.nvim_set_hl(0, "GitlabUnresolved", u.get_colors_for_group(discussion.unresolved))
