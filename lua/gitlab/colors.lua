local state = require("gitlab.state")

local colors = state.settings.colors
local discussion = colors.discussion_tree

vim.api.nvim_set_hl(0, 'GitlabUsername', discussion.username)
vim.api.nvim_set_hl(0, 'GitlabDate', discussion.date)
vim.api.nvim_set_hl(0, 'GitlabChevron', discussion.chevron)
