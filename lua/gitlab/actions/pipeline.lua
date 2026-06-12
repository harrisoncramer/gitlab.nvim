-- This module is responsible for the MR pipeline
-- This lets the user see the current status of the pipeline
-- and retrigger the pipeline from within the editor

local Popup = require("nui.popup")
local state = require("gitlab.state")
local job = require("gitlab.job")
local u = require("gitlab.utils")
local popup = require("gitlab.popup")

local M = {
  pipeline_jobs = {},
  latest_pipeline = nil,
  pipeline_popup = nil,
}

---Return a list of pipeline metadata, if available.
---@return table[]?
local function get_latest_pipelines()
  if state.PIPELINE == nil then
    u.notify("Pipeline state is not initialized", vim.log.levels.WARN)
    return nil
  end

  local pipelines = {}
  for _, pipeline in ipairs(state.PIPELINE) do
    local latest_pipeline = pipeline.latest_pipeline
    if type(latest_pipeline) == "table" and u.table_size(latest_pipeline) > 0 then
      table.insert(pipelines, latest_pipeline)
    end
  end

  if #pipelines == 0 then
    u.notify("No valid pipelines found", vim.log.levels.WARN)
    return nil
  end
  return pipelines
end

---Get the jobs of the idx'th pipeline.
---@param idx integer
---@return table
local function get_pipeline_jobs(idx)
  return u.reverse(type(state.PIPELINE[idx].jobs) == "table" and state.PIPELINE[idx].jobs or {})
end

---Render the Pipeline state in a popup.
M.open = function()
  local latest_pipelines = get_latest_pipelines()
  if not latest_pipelines or #latest_pipelines == 0 then
    return
  end

  local max_width = 0
  local total_height = 0
  local pipelines_data = {}

  for idx, pipeline in ipairs(latest_pipelines) do
    local width = string.len(pipeline.web_url) + 10
    max_width = math.max(max_width, width)

    local pipeline_jobs = get_pipeline_jobs(idx)
    for _, j in ipairs(pipeline_jobs) do
      table.insert(M.pipeline_jobs, j)
    end

    local pipeline_status = M.get_pipeline_status(idx, false)
    local height = 6 + #pipeline_jobs + 3
    total_height = total_height + height

    table.insert(pipelines_data, {
      pipeline = pipeline,
      pipeline_status = pipeline_status,
      jobs = pipeline_jobs,
      width = width,
      height = 6 + #pipeline_jobs + 3,
      lines = {},
    })
  end

  local pipeline_popup = Popup(popup.create_popup_state({
    title = "Loading Pipelines...",
    user_settings = state.settings.popup.pipeline,
    width = max_width,
    height = total_height,
    zindex = 60,
  }))
  popup.set_up_autocommands(pipeline_popup, nil, vim.api.nvim_get_current_win())
  M.pipeline_popup = pipeline_popup
  pipeline_popup:mount()

  local bufnr = vim.api.nvim_get_current_buf()
  vim.opt_local.wrap = false

  u.switch_can_edit_buf(bufnr, true)

  local all_lines = {}
  for i, data in ipairs(pipelines_data) do
    local pipeline = data.pipeline
    local lines = data.lines

    table.insert(lines, data.pipeline_status)
    table.insert(lines, "")
    table.insert(lines, string.format("Last Run: %s", u.time_since(pipeline.created_at)))
    table.insert(lines, string.format("Url: %s", pipeline.web_url))
    table.insert(lines, string.format("Triggered By: %s", pipeline.source))
    table.insert(lines, "")
    table.insert(lines, "Jobs:")

    local max_title_length = u.get_max_length(u.map(data.jobs, function(v)
      return v.name
    end))

    local function row_offset(name)
      local offset = max_title_length - string.len(name)
      local res = string.rep(" ", offset + 5)
      return res
    end

    for _, pipeline_job in ipairs(data.jobs) do
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

    -- Add separator between pipelines
    if i < #pipelines_data then
      table.insert(lines, "")
      table.insert(lines, string.rep("-", max_width))
      table.insert(lines, "")
    end

    for _, line in ipairs(lines) do
      table.insert(all_lines, line)
    end
  end

  vim.schedule(function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, all_lines)

    local line_offset = 0
    for _, data in ipairs(pipelines_data) do
      local pipeline = data.pipeline
      local lines = data.lines

      M.color_status(pipeline.status, bufnr, all_lines[line_offset + 1], line_offset + 1)

      for j, pipeline_job in ipairs(data.jobs) do
        M.color_status(pipeline_job.status, bufnr, all_lines[line_offset + 7 + j], line_offset + 7 + j)
      end

      line_offset = line_offset + #lines
    end

    pipeline_popup.border:set_text("top", "Pipelines Status", "center")
    popup.set_popup_keymaps(pipeline_popup, M.retrigger, M.see_logs)
    u.switch_can_edit_buf(bufnr, false)
  end)
end

---Re-trigger failed pipelines.
M.retrigger = function()
  local pipelines = get_latest_pipelines()
  if not pipelines then
    return
  end

  local failed_pipelines = {}

  for idx, pipeline in ipairs(pipelines) do
    local pipeline_jobs = get_pipeline_jobs(idx)
    for _, pjob in ipairs(pipeline_jobs) do
      if pjob.status == "failed" then
        if pipeline.status ~= "failed" then
          u.notify("Pipeline is not in a failed state!", vim.log.levels.WARN)
          return
        end
        if not failed_pipelines[pipeline.id] then
          job.run_job("/pipeline/trigger/" .. pipeline.id, "POST", nil, function()
            u.notify("Pipeline " .. pipeline.id .. " re-triggered!", vim.log.levels.INFO)
          end)
          failed_pipelines[pipeline.id] = true
        end
      end
    end
  end
end

---Close pipeline popup and open the logs from the job under cursor in a new tab.
M.see_logs = function()
  local bufnr = vim.api.nvim_get_current_buf()
  local linenr = vim.api.nvim_win_get_cursor(0)[1]
  local text = u.get_line_content(bufnr, linenr)

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

    -- TODO: make this configurable - allow users to not close the popup when seeing the logs.
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

---Return the user-defined symbol representing the status of the current pipeline.
---Takes an optional argument to colorize the pipeline icon.
---TODO: This function is only called with `wrap_with_color = false` so
---`M.latest_pipeline` is never accessed - luckily so, because it is never set either,
---so accessing `status` on it would throw an error. Pipeline status coloring is now
---handled differently, so this function can be simplified and probably ultimately
---inlined at call site.
---@param idx integer The index of the pipeline within the table of the latest pipelines
---@param wrap_with_color boolean
---@return string
M.get_pipeline_icon = function(idx, wrap_with_color)
  local symbol = state.settings.pipeline[state.PIPELINE[idx].latest_pipeline.status]
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

---Return the status of the latest pipeline and the symbol representing its status.
---Takes an optional argument to colorize the pipeline icon.
---@param idx integer The index of the pipeline within the table of the latest pipelines
---@param wrap_with_color boolean
---@return string
M.get_pipeline_status = function(idx, wrap_with_color)
  return string.format(
    "[%s]: Status: %s (%s)",
    state.PIPELINE[idx].name,
    M.get_pipeline_icon(idx, wrap_with_color),
    state.PIPELINE[idx].latest_pipeline.status
  )
end

---Colorize the pipeline status line.
---@param status "canceled"|"created"|"failed"|"pending"|"preparing"|"running"|"scheduled"|"skipped"|"success"
---@param bufnr integer The buffer number of the pipeline popup
---@param status_line string The content of the given line (used to calculate offset for extmark)
---@param linenr integer The line number in the pipeline popup to colorize
M.color_status = function(status, bufnr, status_line, linenr)
  local ns_id = vim.api.nvim_create_namespace("GitlabNamespace")
  -- TODO: The following line is probably dead code. It sets guifg to an icon like "" and
  -- StatusHighlight is never used.
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
    linenr - 1,
    0,
    { end_row = linenr - 1, end_col = string.len(status_line), hl_group = status_to_color_map[status] }
  )
end

return M
