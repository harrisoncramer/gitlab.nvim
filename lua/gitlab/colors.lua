local state = require("gitlab.state")

-- Set icons into global vim variables for syntax matching
-- TODO: This could be simplified to assigning the discussion_tree table to
-- vim.g.gitlab_discussion_tree and accessing it as a vim dictionary in
-- after/syntax/gitlab.vim.
local discussion_tree = state.settings.discussion_tree
vim.g.gitlab_discussion_tree_expander_open = discussion_tree.expanders.expanded
vim.g.gitlab_discussion_tree_expander_closed = discussion_tree.expanders.collapsed
vim.g.gitlab_discussion_tree_draft = discussion_tree.draft
vim.g.gitlab_discussion_tree_resolved = discussion_tree.resolved
vim.g.gitlab_discussion_tree_unresolved = discussion_tree.unresolved
vim.g.gitlab_discussion_tree_unlinked = discussion_tree.unlinked

local discussion_colors = state.settings.colors.discussion_tree

local function get_colors_for_group(group)
  local normal_fg = vim.fn.synIDattr(vim.fn.synIDtrans(vim.fn.hlID(group)), "fg")
  local normal_bg = vim.fn.synIDattr(vim.fn.synIDtrans(vim.fn.hlID(group)), "bg")
  return { fg = normal_fg, bg = normal_bg }
end
vim.api.nvim_create_autocmd({ "VimEnter", "ColorScheme" }, {
  callback = function()
    vim.api.nvim_set_hl(0, "GitlabUsername", get_colors_for_group(discussion_colors.username))
    vim.api.nvim_set_hl(0, "GitlabMention", get_colors_for_group(discussion_colors.mention))
    vim.api.nvim_set_hl(0, "GitlabDate", get_colors_for_group(discussion_colors.date))
    vim.api.nvim_set_hl(0, "GitlabExpander", get_colors_for_group(discussion_colors.expander))
    vim.api.nvim_set_hl(0, "GitlabDirectory", get_colors_for_group(discussion_colors.directory))
    vim.api.nvim_set_hl(0, "GitlabDirectoryIcon", get_colors_for_group(discussion_colors.directory_icon))
    vim.api.nvim_set_hl(0, "GitlabFileName", get_colors_for_group(discussion_colors.file_name))
    vim.api.nvim_set_hl(0, "GitlabResolved", get_colors_for_group(discussion_colors.resolved))
    vim.api.nvim_set_hl(0, "GitlabUnresolved", get_colors_for_group(discussion_colors.unresolved))
    vim.api.nvim_set_hl(0, "GitlabCommit", get_colors_for_group(discussion_colors.commit))
    vim.api.nvim_set_hl(0, "GitlabUnlinked", get_colors_for_group(discussion_colors.unlinked))
    vim.api.nvim_set_hl(0, "GitlabDraft", get_colors_for_group(discussion_colors.draft))
    vim.api.nvim_set_hl(0, "GitlabDraftMode", get_colors_for_group(discussion_colors.draft_mode))
    vim.api.nvim_set_hl(0, "GitlabLiveMode", get_colors_for_group(discussion_colors.live_mode))
    vim.api.nvim_set_hl(0, "GitlabSortMethod", get_colors_for_group(discussion_colors.sort_method))
  end,
})
