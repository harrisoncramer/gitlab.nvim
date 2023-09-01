-- This module is responsible for the MR pipline
-- This lets the user see the current status of the pipeline
-- and retrigger the pipeline from within the editor
local Popup          = require("nui.popup")
local state          = require("gitlab.state")
local u              = require("gitlab.utils")
local M              = {}

local pipeline_popup = Popup(u.create_popup_state("Loading Pipeline...", "40%", 6))

-- The function will render the Pipeline state in a popup
M.open               = function()
  pipeline_popup:mount()
  local bufnr = vim.api.nvim_get_current_buf()
  local pipeline = state.INFO.pipeline
  if pipeline == nil or (type(pipeline) == "table" and u.table_size(pipeline) == 0) then
    vim.notify("Pipeline information not found", vim.log.levels.WARN)
    return
  end

  local lines = {}

  table.insert(lines, string.format("Status: %s (%s)", state.settings.pipeline[pipeline.status].symbol, pipeline.status))
  table.insert(lines, "")
  table.insert(lines, string.format("Last Run: %s", u.format_date(pipeline.created_at)))
  table.insert(lines, string.format("Url: %s", pipeline.web_url))
  table.insert(lines, string.format("Triggered By: %s", pipeline.status))

  vim.schedule(function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    M.color_status(pipeline.status, bufnr, lines[1])
    pipeline_popup.border:set_text("top", "Pipeline Status", "center")
    state.set_popup_keymaps(pipeline_popup, M.edit_description)
  end)
end

M.color_status       = function(status, bufnr, status_line)
  local ns_id = vim.api.nvim_create_namespace("GitlabNamespace")
  vim.cmd(string.format("highlight default StatusHighlight guifg=%s", state.settings.pipeline[status].color))

  local linnr = 1
  vim.api.nvim_buf_set_extmark(bufnr, ns_id, linnr - 1, 0,
    { end_row = linnr - 1, end_col = string.len(status_line), hl_group = 'StatusHighlight' })
end

return M
