local core = require("gitlab_nvim")
local u = require("gitlab_nvim.utils")

local function send()
  local text = u.get_buffer_text(core.popup.bufnr)
  core.popup:unmount()
  core.sendComment(text)
end

local function exit()
  core.popup:unmount()
end

vim.keymap.set('n', '<Esc>', exit, { buffer = true })
vim.keymap.set('n', ':', '', { buffer = true })
vim.keymap.set('n', '<leader>s', send, { buffer = true })
