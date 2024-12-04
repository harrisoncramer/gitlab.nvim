-- This module is responsible for the MR pipeline
-- This lets the user see the current status of the pipeline
-- and retrigger the pipeline from within the editor
local Popup = require("nui.popup")
local state = require("gitlab.state")
local job = require("gitlab.job")
local u = require("gitlab.utils")
local popup = require("gitlab.popup")
local M = {
  pipeline_jobs = nil,
  latest_pipeline = nil,
  pipeline_popup = nil,
}

local function get_latest_pipeline()
  local pipeline = state.PIPELINE and state.PIPELINE.latest_pipeline
  if type(pipeline) ~= "table" or (type(pipeline) == "table" and u.table_size(pipeline) == 0) then
    u.notify("Pipeline not found", vim.log.levels.WARN)
    return
  end
  return pipeline
end

local function get_pipeline_jobs()
  M.latest_pipeline = get_latest_pipeline()
  if not M.latest_pipeline then
    return
  end
  return u.reverse(type(state.PIPELINE.jobs) == "table" and state.PIPELINE.jobs or {})
end

-- The function will render the Pipeline state in a popup
M.open = function()
  M.pipeline_jobs = get_pipeline_jobs()
  M.latest_pipeline = get_latest_pipeline()
  if M.latest_pipeline == nil then
    return
  end

  local width = string.len(M.latest_pipeline.web_url) + 10
  local height = 6 + #M.pipeline_jobs + 3

  local pipeline_popup =
    Popup(popup.create_popup_state("Loading Pipeline...", state.settings.popup.pipeline, width, height, 60))
  popup.set_up_autocommands(pipeline_popup, nil, vim.api.nvim_get_current_win())
  M.pipeline_popup = pipeline_popup
  pipeline_popup:mount()

  local bufnr = vim.api.nvim_get_current_buf()
  vim.opt_local.wrap = false

  local lines = {}

  u.switch_can_edit_buf(bufnr, true)
  table.insert(lines, "Status: " .. M.get_pipeline_status(false))
  table.insert(lines, "")
  table.insert(lines, string.format("Last Run: %s", u.time_since(M.latest_pipeline.created_at)))
  table.insert(lines, string.format("Url: %s", M.latest_pipeline.web_url))
  table.insert(lines, string.format("Triggered By: %s", M.latest_pipeline.source))

  table.insert(lines, "")
  table.insert(lines, "Jobs:")

  local longest_title = u.get_longest_string(u.map(M.pipeline_jobs, function(v)
    return v.name
  end))

  local function row_offset(name)
    local offset = longest_title - string.len(name)
    local res = string.rep(" ", offset + 5)
    return res
  end

  for _, pipeline_job in ipairs(M.pipeline_jobs) do
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
    M.color_status(M.latest_pipeline.status, bufnr, lines[1], 1)

    for i, pipeline_job in ipairs(M.pipeline_jobs) do
      M.color_status(pipeline_job.status, bufnr, lines[7 + i], 7 + i)
    end

    pipeline_popup.border:set_text("top", "Pipeline Status", "center")
    popup.set_popup_keymaps(pipeline_popup, M.retrigger, M.see_logs)
    u.switch_can_edit_buf(bufnr, false)
  end)
end

M.retrigger = function()
  M.latest_pipeline = get_latest_pipeline()
  if not M.latest_pipeline then
    return
  end
  if M.latest_pipeline.status ~= "failed" then
    u.notify("Pipeline is not in a failed state!", vim.log.levels.WARN)
    return
  end

  job.run_job("/pipeline/" .. M.latest_pipeline.id, "POST", nil, function()
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
  for _, pipeline_job in ipairs(M.pipeline_jobs) do
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

    local lines = u.lines_into_table(file)

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

---Returns the user-defined symbol representing the status
---of the current pipeline. Takes an optional argument to
---colorize the pipeline icon.
---@param wrap_with_color boolean
---@return string
M.get_pipeline_icon = function(wrap_with_color)
  M.latest_pipeline = get_latest_pipeline()
  if not M.latest_pipeline then
    return ""
  end
  local symbol = state.settings.pipeline[M.latest_pipeline.status]
  if not wrap_with_color then
    return symbol
  end
  if M.latest_pipeline.status == "failed" then
    return "%#DiagnosticError#" .. symbol
  end
  if M.latest_pipeline.status == "success" then
    return "%#DiagnosticOk#" .. symbol
  end
  return "%#DiagnosticWarn#" .. symbol
end

---Returns the status of the latest pipeline and the symbol
--representing the status of the current pipeline. Takes an optional argument to
---colorize the pipeline icon.
---@param wrap_with_color boolean
---@return string
M.get_pipeline_status = function(wrap_with_color)
  M.latest_pipeline = get_latest_pipeline()
  if not M.latest_pipeline then
    return ""
  end
  return string.format("%s (%s)", M.get_pipeline_icon(wrap_with_color), M.latest_pipeline.status)
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
