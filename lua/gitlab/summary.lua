local job              = require("gitlab.job")
local state            = require("gitlab.state")
local Popup            = require("nui.popup")
local u                = require("gitlab.utils")
local keymaps          = require("gitlab.keymaps")
local descriptionPopup = Popup(u.create_popup_state("Loading Description...", "80%", "80%"))
local M                = {}

M.summary              = function()
  if u.base_invalid() then return end
  descriptionPopup:mount()
  local currentBuffer = vim.api.nvim_get_current_buf()
  local title = state.INFO.title
  local description = state.INFO.description
  local lines = {}
  for line in description:gmatch("[^\n]+") do
    table.insert(lines, line)
    table.insert(lines, "")
  end
  vim.schedule(function()
    vim.api.nvim_buf_set_lines(currentBuffer, 0, -1, false, lines)
    descriptionPopup.border:set_text("top", title, "center")
    keymaps.set_popup_keymaps(descriptionPopup, M.edit_description)
  end)
end

M.edit_description     = function(text)
  local jsonTable = { description = text }
  local json = vim.json.encode(jsonTable)
  job.run_job("mr/description", "PUT", json, function(data)
    vim.notify(data.message, vim.log.levels.INFO)
    state.INFO.description = data.mr.description
  end)
end

return M
