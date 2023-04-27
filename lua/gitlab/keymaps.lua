local u             = require("gitlab.utils")
local state         = require("gitlab.state")
local M             = {}

M.set_popup_keymaps = function(popup, action)
  vim.keymap.set('n', state.keymaps.popup.exit, function() u.exit(popup) end, { buffer = true })
  vim.keymap.set('n', ':', '', { buffer = true })
  if action ~= nil then
    vim.keymap.set('n', state.keymaps.popup.perform_action, function()
      local text = u.get_buffer_text(popup.bufnr)
      popup:unmount()
      action(text)
    end, { buffer = true })
  end
end

M.set_keymap_keys   = function(keyTable)
  if keyTable == nil then return end
  state.keymaps = u.merge_tables(state.keymaps, keyTable)
end

M.set_keymaps       = function()
  local ok, _ = pcall(require, "diffview")
  vim.keymap.set("n", state.keymaps.review.toggle, function()
    if not ok then
      require("notify")("You must have diffview.nvim installed to use this command!", "error")
      return
    end
    local isDiff = vim.fn.getwinvar(nil, "&diff")
    local bufName = vim.api.nvim_buf_get_name(0)
    local has_develop = u.branch_exists("main") -- TODO: Write this function
    if not has_develop then
      require("notify")('No ' .. state.BASE_BRANCH .. ' branch, cannot review.', "error")
      return
    end
    if isDiff ~= 0 or u.string_starts(bufName, "diff") then
      vim.cmd.tabclose()
      vim.cmd.tabprev()
    else
      vim.cmd.DiffviewOpen(state.BASE_BRANCH)
      u.press_enter()
    end
  end)
end



return M
