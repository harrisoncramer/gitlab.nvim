local state = require("gitlab.state")
local u = require("gitlab.utils")

local colors = state.settings.colors
local discussion = colors.discussion_tree

vim.api.nvim_set_hl(0, "GitlabUsername", u.get_colors_for_group(discussion.username))
vim.api.nvim_set_hl(0, "GitlabDate", u.get_colors_for_group(discussion.date))
vim.api.nvim_set_hl(0, "GitlabChevron", u.get_colors_for_group(discussion.chevron))
vim.api.nvim_set_hl(0, "GitlabDirectory", u.get_colors_for_group(discussion.directory))
vim.api.nvim_set_hl(0, "GitlabDirectoryIcon", u.get_colors_for_group(discussion.directory_icon))
vim.api.nvim_set_hl(0, "GitlabFileName", u.get_colors_for_group(discussion.file_name))
