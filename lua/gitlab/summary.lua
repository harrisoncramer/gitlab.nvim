local job          = require("gitlab.job")
local state        = require("gitlab.state")
local Popup        = require("nui.popup")
local u            = require("gitlab.utils")
local keymaps      = require("gitlab.keymaps")
local summaryPopup = Popup(u.create_popup_state("Loading Summary...", "80%", "80%"))
local M            = {}

M.summary          = function()
  if u.base_invalid() then return end
  summaryPopup:mount()
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
    summaryPopup.border:set_text("top", title, "center")
    keymaps.set_popup_keymaps(summaryPopup, M.edit_summary)
  end)
end

M.edit_summary     = function(text)
  local jsonTable = { description = text }
  local json = vim.json.encode(jsonTable)
  job.run_job("mr", "PUT", json, function(data)
    vim.notify(data.message, vim.log.levels.INFO)
    state.INFO.description = data.mr.description
  end)
end

return M
