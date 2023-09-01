-- This module is responsible for the MR pipline
-- This lets the user see the current status of the pipeline
-- and retrigger the pipeline from within the editor
local Popup    = require("nui.popup")
local state    = require("gitlab.state")
local job      = require("gitlab.job")
local u        = require("gitlab.utils")
local M        = {}

-- The function will render the Pipeline state in a popup
M.open         = function()
  local pipeline = state.INFO.pipeline

  if pipeline == nil or (type(pipeline) == "table" and u.table_size(pipeline) == 0) then
    vim.notify("Pipeline information not found", vim.log.levels.WARN)
    return
  end

  local width = string.len(pipeline.web_url) + 10
  local height = 6

  local pipeline_popup = Popup(u.create_popup_state("Loading Pipeline...", width, height))
  pipeline_popup:mount()

  local bufnr = vim.api.nvim_get_current_buf()
  vim.opt_local.wrap = false
  local lines = {}

  u.switch_can_edit_buf(bufnr, true)
  table.insert(lines, string.format("Status: %s (%s)", state.settings.pipeline[pipeline.status].symbol, pipeline.status))
  table.insert(lines, "")
  table.insert(lines, string.format("Last Run: %s", u.format_date(pipeline.created_at)))
  table.insert(lines, string.format("Url: %s", pipeline.web_url))
  table.insert(lines, string.format("Triggered By: %s", pipeline.source))

  vim.schedule(function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    M.color_status(pipeline.status, bufnr, lines[1])
    pipeline_popup.border:set_text("top", "Pipeline Status", "center")
    state.set_popup_keymaps(pipeline_popup, M.retrigger)
    u.switch_can_edit_buf(bufnr, false)
  end)
end

M.retrigger    = function()
  local body = { pipeline_id = state.INFO.pipeline.id }
  if state.INFO.pipeline.status == 'success' then
    vim.notify("Pipeline has already passed!", vim.log.levels.WARN)
    return
  end

  job.run_job("/pipeline", "POST", body, function(data)
    vim.notify("Pipeline re-triggered!", vim.log.levels.INFO)
    state.INFO.pipeline = data.pipeline
  end)
end

M.color_status = function(status, bufnr, status_line)
  local ns_id = vim.api.nvim_create_namespace("GitlabNamespace")
  vim.cmd(string.format("highlight default StatusHighlight guifg=%s", state.settings.pipeline[status].color))

  local linnr = 1
  vim.api.nvim_buf_set_extmark(bufnr, ns_id, linnr - 1, 0,
    { end_row = linnr - 1, end_col = string.len(status_line), hl_group = 'StatusHighlight' })
end

return M
