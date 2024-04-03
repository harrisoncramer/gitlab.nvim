-- This module is responsible for the MR pipeline
-- This lets the user see the current status of the pipeline
-- and retrigger the pipeline from within the editor
local Popup = require("nui.popup")
local state = require("gitlab.state")
local job = require("gitlab.job")
local u = require("gitlab.utils")
local M = {
  pipeline_popup = nil,
  pipeline = nil,
}

local function pipeline_exists()
  if type(state.JOBS) ~= "table" or (type(state.JOBS) == "table" and u.table_size(state.JOBS) == 0) then
    u.notify("Pipeline not found", vim.log.levels.WARN)
    return
  end
  return true
end

local set_recent_pipeline = function()
  if not pipeline_exists() then
    return nil
  end
  M.pipeline = state.JOBS[1]
end

M.get_pipeline_status = function()
  return string.format("%s (%s)", state.settings.pipeline[M.pipeline.status], M.pipeline.status)
end

-- The function will render the Pipeline state in a popup
M.open = function()
  set_recent_pipeline()
  if not M.pipeline then
    return
  end

  local width = string.len(M.pipeline.web_url) + 10
  local height = 6 + #state.JOBS + 3

  local pipeline_popup =
      Popup(u.create_popup_state("Loading Pipeline...", state.settings.popup.pipeline, width, height, 60))
  M.pipeline_popup = pipeline_popup
  pipeline_popup:mount()

  local bufnr = vim.api.nvim_get_current_buf()
  vim.opt_local.wrap = false

  local lines = {}

  u.switch_can_edit_buf(bufnr, true)
  table.insert(lines, "Status: " .. M.get_pipeline_status())
  table.insert(lines, "")
  table.insert(lines, string.format("Last Run: %s", u.time_since(M.pipeline.created_at)))
  table.insert(lines, string.format("Url: %s", M.pipeline.web_url))
  table.insert(lines, string.format("Triggered By: %s", M.pipeline.source))

  table.insert(lines, "")
  table.insert(lines, "Jobs:")

  local longest_title = u.get_longest_string(u.map(state.JOBS, function(v)
    return v.name
  end))

  local function row_offset(name)
    local offset = longest_title - string.len(name)
    local res = string.rep(" ", offset + 5)
    return res
  end

  for _, pipeline_job in ipairs(state.JOBS) do
    local offset = row_offset(pipeline_job.name)
    local row = string.format(
      "%s%s %s (%s)",
      pipeline_job.name,
      offset,
      state.settings.pipeline[pipeline_job.status] or "*",
      pipeline_job.status or ""
    )

    table.insert(lines, row)
  end

  vim.schedule(function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    M.color_status(M.pipeline.status, bufnr, lines[1], 1)

    for i, pipeline_job in ipairs(state.JOBS) do
      M.color_status(pipeline_job.status, bufnr, lines[7 + i], 7 + i)
    end

    pipeline_popup.border:set_text("top", "Pipeline Status", "center")
    state.set_popup_keymaps(pipeline_popup, M.retrigger, M.see_logs)
    u.switch_can_edit_buf(bufnr, false)
  end)
end

M.retrigger = function()
  if not M.pipeline then
    return
  end

  if M.pipeline.status ~= "failed" then
    u.notify("Pipeline is not in a failed state!", vim.log.levels.WARN)
    return
  end

  job.run_job("/pipeline/" .. pipeline.id, "POST", nil, function()
    u.notify("Pipeline re-triggered!", vim.log.levels.INFO)
  end)
end

M.see_logs = function()
  local bufnr = vim.api.nvim_get_current_buf()
  local linnr = vim.api.nvim_win_get_cursor(0)[1]
  local text = u.get_line_content(bufnr, linnr)

  local job_name = string.match(text, "(.-)%s%s%s%s%s")

  if job_name == nil then
    u.notify("Cannot find job name", vim.log.levels.ERROR)
    return
  end

  local j = nil
  for _, pipeline_job in ipairs(state.JOBS) do
    if pipeline_job.name == job_name then
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
    for line in u.split_by_new_lines(file) do
      table.insert(lines, line)
    end

    if #lines == 0 then
      u.notify("Log trace lines could not be parsed", vim.log.levels.ERROR)
      return
    end

    M.pipeline_popup:unmount()

    vim.cmd.tabnew()
    bufnr = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

    local temp_file = os.tmpname()
    local job_file_path = string.format(temp_file, j.id)

    vim.cmd("w! " .. job_file_path)
    vim.cmd("term cat " .. job_file_path)

    vim.api.nvim_buf_set_name(0, job_name)
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
