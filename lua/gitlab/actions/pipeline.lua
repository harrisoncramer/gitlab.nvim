-- This module is responsible for the MR pipline
-- This lets the user see the current status of the pipeline
-- and retrigger the pipeline from within the editor
local Popup = require("nui.popup")
local state = require("gitlab.state")
local job = require("gitlab.job")
local u = require("gitlab.utils")
local M = {
  pipeline_jobs = nil,
  pipeline_popup = nil,
}

local function get_pipeline()
  local pipeline = state.INFO.head_pipeline or state.INFO.pipeline

  if type(pipeline) ~= "table" or (type(pipeline) == "table" and u.table_size(pipeline) == 0) then
    u.notify("Pipeline not found", vim.log.levels.WARN)
    return
  end
  return pipeline
end

-- The function will render the Pipeline state in a popup
M.open = function()
  local pipeline = get_pipeline()
  if not pipeline then
    return
  end
  local body = { pipeline_id = pipeline.id }
  job.run_job("/pipeline", "GET", body, function(data)
    local pipeline_jobs = u.reverse(type(data.Jobs) == "table" and data.Jobs or {})
    M.pipeline_jobs = pipeline_jobs

    local width = string.len(pipeline.web_url) + 10
    local height = 6 + #pipeline_jobs + 3

    local pipeline_popup = Popup(u.create_popup_state("Loading Pipeline...", width, height))
    M.pipeline_popup = pipeline_popup
    pipeline_popup:mount()

    local bufnr = vim.api.nvim_get_current_buf()
    vim.opt_local.wrap = false

    local lines = {}

    u.switch_can_edit_buf(bufnr, true)
    table.insert(lines, string.format("Status: %s (%s)", state.settings.pipeline[pipeline.status], pipeline.status))
    table.insert(lines, "")
    table.insert(lines, string.format("Last Run: %s", u.time_since(pipeline.created_at)))
    table.insert(lines, string.format("Url: %s", pipeline.web_url))
    table.insert(lines, string.format("Triggered By: %s", pipeline.source))

    table.insert(lines, "")
    table.insert(lines, "Jobs:")
    for _, pipeline_job in ipairs(pipeline_jobs) do
      table.insert(
        lines,
        string.format(
          "%s (%s) %s",
          state.settings.pipeline[pipeline_job.status],
          pipeline_job.status,
          pipeline_job.name
        )
      )
    end

    vim.schedule(function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
      M.color_status(pipeline.status, bufnr, lines[1], 1)

      for i, pipeline_job in ipairs(pipeline_jobs) do
        M.color_status(pipeline_job.status, bufnr, lines[7 + i], 7 + i)
      end

      pipeline_popup.border:set_text("top", "Pipeline Status", "center")
      state.set_popup_keymaps(pipeline_popup, M.retrigger, M.see_logs)
      u.switch_can_edit_buf(bufnr, false)
    end)
  end)
end

M.retrigger = function()
  local pipeline = get_pipeline()
  if not pipeline then
    return
  end
  local body = { pipeline_id = pipeline.id }
  if pipeline.status ~= "failed" then
    u.notify("Pipeline is not in a failed state!", vim.log.levels.WARN)
    return
  end

  job.run_job("/pipeline", "POST", body, function()
    u.notify("Pipeline re-triggered!", vim.log.levels.INFO)
  end)
end

M.see_logs = function()
  local bufnr = vim.api.nvim_get_current_buf()
  local linnr = vim.api.nvim_win_get_cursor(0)[1]
  local text = u.get_line_content(bufnr, linnr)
  local last_word = u.get_last_word(text)
  if last_word == nil then
    u.notify("Cannot find job name", vim.log.levels.ERROR)
    return
  end

  local j = nil
  for _, pipeline_job in ipairs(M.pipeline_jobs) do
    if pipeline_job.name == last_word then
      j = pipeline_job
    end
  end

  if j == nil then
    u.notify("Cannot find job in state", vim.log.levels.ERROR)
    return
  end

  local body = { job_id = j.id }
  job.run_job("/job", "GET", body, function(data)
    local file = data.file
    if file == "" then
      u.notify("Log trace is empty", vim.log.levels.WARN)
      return
    end

    local lines = {}
    for line in file:gmatch("[^\n]+") do
      table.insert(lines, line)
    end

    if #lines == 0 then
      u.notify("Log trace lines could not be parsed", vim.log.levels.ERROR)
      return
    end

    M.pipeline_popup:unmount()
    vim.cmd.enew()

    bufnr = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

    -- TODO: Fix for Windows
    local job_file_path = string.format("/tmp/gitlab.nvim.job-%d", j.id)
    vim.cmd("w! " .. job_file_path)
    vim.cmd.bd()

    vim.cmd.enew()
    vim.cmd("term cat " .. job_file_path)
  end)
end

M.color_status = function(status, bufnr, status_line, linnr)
  local ns_id = vim.api.nvim_create_namespace("GitlabNamespace")
  vim.cmd(string.format("highlight default StatusHighlight guifg=%s", state.settings.pipeline[status]))

  local status_to_color_map = {
    created = "DiagnosticWarn",
    pending = "DiagnosticWarn",
    preparing = "DiagnosticWarn",
    scheduled = "DiagnosticWarn",
    running = "DiagnosticWarn",
    canceled = "DiagnosticWarn",
    skipped = "DiagnosticWarn",
    failed = "DiagnosticError",
    success = "DiagnosticOK",
  }

  vim.api.nvim_buf_set_extmark(
    bufnr,
    ns_id,
    linnr - 1,
    0,
    { end_row = linnr - 1, end_col = string.len(status_line), hl_group = status_to_color_map[status] }
  )
end

return M
