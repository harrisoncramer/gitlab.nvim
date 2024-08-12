local state = require("gitlab.state")
local u = require("gitlab.utils")

local colors = state.settings.colors

-- Set icons into global vim variables for syntax matching
local expanders = state.settings.discussion_tree.expanders
vim.g.gitlab_discussion_tree_expander_open = expanders.expanded
vim.g.gitlab_discussion_tree_expander_closed = expanders.collapsed
vim.g.gitlab_discussion_tree_draft = ""
vim.g.gitlab_discussion_tree_resolved = "✓"
vim.g.gitlab_discussion_tree_unresolved = "-"

local discussion = colors.discussion_tree
vim.api.nvim_set_hl(0, "GitlabUsername", u.get_colors_for_group(discussion.username))
vim.api.nvim_set_hl(0, "GitlabMention", u.get_colors_for_group(discussion.mention))
vim.api.nvim_set_hl(0, "GitlabDate", u.get_colors_for_group(discussion.date))
vim.api.nvim_set_hl(0, "GitlabExpander", u.get_colors_for_group(discussion.expander))
vim.api.nvim_set_hl(0, "GitlabDirectory", u.get_colors_for_group(discussion.directory))
vim.api.nvim_set_hl(0, "GitlabDirectoryIcon", u.get_colors_for_group(discussion.directory_icon))
vim.api.nvim_set_hl(0, "GitlabFileName", u.get_colors_for_group(discussion.file_name))
vim.api.nvim_set_hl(0, "GitlabResolved", u.get_colors_for_group(discussion.resolved))
vim.api.nvim_set_hl(0, "GitlabUnresolved", u.get_colors_for_group(discussion.unresolved))
vim.api.nvim_set_hl(0, "GitlabDraft", u.get_colors_for_group(discussion.draft))
