-- This module is responsible for the MR description
-- This lets the user open the description in a popup and
-- send edits to the description back to Gitlab
local Layout = require("nui.layout")
local Popup = require("nui.popup")
local job = require("gitlab.job")
local u = require("gitlab.utils")
local List = require("gitlab.utils.list")
local state = require("gitlab.state")
local miscellaneous = require("gitlab.actions.miscellaneous")

local M = {
  layout_visible = false,
  layout = nil,
  layout_buf = nil,
  title_bufnr = nil,
  description_bufnr = nil,
}

-- The function will render a popup containing the MR title and MR description, and optionally,
-- any additional metadata that the user wants. The title and description are editable and
-- can be changed via the local action keybinding, which also closes the popup
M.summary = function()
  if M.layout_visible then
    M.layout:unmount()
    M.layout_visible = false
    return
  end

  local title = state.INFO.title
  local description_lines = M.build_description_lines()
  local info_lines = state.settings.info.enabled and M.build_info_lines() or { "" }

  local layout, title_popup, description_popup, info_popup = M.create_layout(info_lines)
  local popups = {
    title_popup,
    description_popup,
    info_popup,
  }

  M.layout = layout
  M.layout_buf = layout.bufnr
  M.layout_visible = true

  local function exit()
    layout:unmount()
    M.layout_visible = false
  end

  vim.schedule(function()
    vim.api.nvim_buf_set_lines(description_popup.bufnr, 0, -1, false, description_lines)
    vim.api.nvim_buf_set_lines(title_popup.bufnr, 0, -1, false, { title })

    if info_popup then
      vim.api.nvim_buf_set_lines(info_popup.bufnr, 0, -1, false, info_lines)
      u.switch_can_edit_buf(info_popup.bufnr, false)
      M.color_details(info_popup.bufnr) -- Color values in details popup
    end

    state.set_popup_keymaps(
      description_popup,
      M.edit_summary,
      miscellaneous.attach_file,
      { cb = exit, action_before_close = true }
    )
    state.set_popup_keymaps(title_popup, M.edit_summary, nil, { cb = exit, action_before_close = true })
    state.set_popup_keymaps(info_popup, M.edit_summary, nil, { cb = exit, action_before_close = true })
    miscellaneous.set_cycle_popups_keymaps(popups)

    vim.api.nvim_set_current_buf(description_popup.bufnr)
  end)
end

-- Builds a lua list of strings that contain the MR description
M.build_description_lines = function()
  local description_lines = {}

  local description = state.INFO.description
  for line in u.split_by_new_lines(description) do
    table.insert(description_lines, line)
  end
  -- TODO: @harrisoncramer Not sure whether the following line should be here at all. It definitely
  -- didn't belong into the for loop, since it inserted an empty line after each line. But maybe
  -- there is a purpose for an empty line at the end of the buffer?
  table.insert(description_lines, "")

  return description_lines
end

-- Builds a lua list of strings that contain metadata about the current MR. Only builds the
-- lines that users include in their state.settings.info.fields list.
M.build_info_lines = function()
  local info = state.INFO
  local options = {
    author = { title = "Author", content = "@" .. info.author.username .. " (" .. info.author.name .. ")" },
    created_at = { title = "Created", content = u.format_to_local(info.created_at, vim.fn.strftime("%z")) },
    updated_at = { title = "Updated", content = u.format_to_local(info.updated_at, vim.fn.strftime("%z")) },
    detailed_merge_status = { title = "Status", content = info.detailed_merge_status },
    draft = { title = "Draft", content = (info.draft and "Yes" or "No") },
    conflicts = { title = "Merge Conflicts", content = (info.has_conflicts and "Yes" or "No") },
    assignees = { title = "Assignees", content = u.make_readable_list(info.assignees, "name") },
    reviewers = { title = "Reviewers", content = u.make_readable_list(info.reviewers, "name") },
    branch = { title = "Branch", content = info.source_branch },
    labels = { title = "Labels", content = table.concat(info.labels, ", ") },
    target_branch = { title = "Target Branch", content = info.target_branch },
    delete_branch = { title = "Delete Source Branch", content = (info.force_remove_source_branch and "Yes" or "No") },
    squash = { title = "Squash Commits", content = (info.squash and "Yes" or "No") },
    pipeline = {
      title = "Pipeline Status",
      content = function()
        local pipeline = state.INFO.pipeline
        if type(pipeline) ~= "table" or (type(pipeline) == "table" and u.table_size(pipeline) == 0) then
          return ""
        end
        return pipeline.status
      end,
    },
  }

  local longest_used = ""
  for _, v in ipairs(state.settings.info.fields) do
    if v == "merge_status" then
      v = "detailed_merge_status"
    end -- merge_status was deprecated, see https://gitlab.com/gitlab-org/gitlab/-/issues/3169#note_1162532204
    local title = options[v].title
    if string.len(title) > string.len(longest_used) then
      longest_used = title
    end
  end

  local function row_offset(row)
    local offset = string.len(longest_used) - string.len(row)
    return string.rep(" ", offset + 3)
  end

  return List.new(state.settings.info.fields):map(function(v)
    if v == "merge_status" then
      v = "detailed_merge_status"
    end
    local row = options[v]
    local line = "* " .. row.title .. row_offset(row.title)
    if type(row.content) == "function" then
      local content = row.content()
      if content ~= nil then
        line = line .. row.content()
      end
    else
      line = line .. row.content
    end
    return line
  end)
end

-- This function will PUT the new description to the Go server
M.edit_summary = function()
  local description = u.get_buffer_text(M.description_bufnr)
  local title = u.get_buffer_text(M.title_bufnr):gsub("\n", " ")
  local body = { title = title, description = description }
  job.run_job("/mr/summary", "PUT", body, function(data)
    u.notify(data.message, vim.log.levels.INFO)
    state.INFO.description = data.mr.description
    state.INFO.title = data.mr.title
    M.layout:unmount()
    M.layout_visible = false
  end)
end

M.create_layout = function(info_lines)
  local title_popup = Popup(u.create_box_popup_state(nil, false))
  M.title_bufnr = title_popup.bufnr
  local description_popup = Popup(u.create_box_popup_state("Description", true))
  M.description_bufnr = description_popup.bufnr
  local details_popup

  local internal_layout
  if state.settings.info.enabled then
    details_popup = Popup(u.create_box_popup_state("Details", false))
    if state.settings.info.horizontal then
      local longest_line = u.get_longest_string(info_lines)
      internal_layout = Layout.Box({
        Layout.Box(title_popup, { size = 3 }),
        Layout.Box({
          Layout.Box(details_popup, { size = longest_line + 3 }),
          Layout.Box(description_popup, { grow = 1 }),
        }, { dir = "row", size = "100%" }),
      }, { dir = "col" })
    else
      internal_layout = Layout.Box({
        Layout.Box(title_popup, { size = 3 }),
        Layout.Box(description_popup, { grow = 1 }),
        Layout.Box(details_popup, { size = #info_lines + 3 }),
      }, { dir = "col" })
    end
  else
    internal_layout = Layout.Box({
      Layout.Box(title_popup, { size = 3 }),
      Layout.Box(description_popup, { grow = 1 }),
    }, { dir = "col" })
  end

  local layout = Layout({
    position = "50%",
    relative = "editor",
    size = {
      width = "95%",
      height = "95%",
    },
  }, internal_layout)

  layout:mount()
  return layout, title_popup, description_popup, details_popup
end

M.color_details = function(bufnr)
  local details_namespace = vim.api.nvim_create_namespace("Details")
  for i, v in ipairs(state.settings.info.fields) do
    if v == "labels" then
      local line_content = u.get_line_content(bufnr, i)
      for j, label in ipairs(state.LABELS) do
        local start_idx, end_idx = line_content:find(label.Name)
        if start_idx ~= nil and end_idx ~= nil then
          vim.cmd("highlight " .. "label" .. j .. " guifg=white")
          vim.api.nvim_set_hl(0, ("label" .. j), { fg = label.Color })
          vim.api.nvim_buf_add_highlight(bufnr, details_namespace, ("label" .. j), i - 1, start_idx - 1, end_idx)
        end
      end
    elseif v == "delete_branch" or v == "squash" or v == "draft" or v == "conflicts" then
      local line_content = u.get_line_content(bufnr, i)
      local start_idx, end_idx = line_content:find("%S-$")
      if start_idx ~= nil and end_idx ~= nil then
        vim.api.nvim_set_hl(0, "boolean", { link = "Constant" })
        vim.api.nvim_buf_add_highlight(bufnr, details_namespace, "boolean", i - 1, start_idx - 1, end_idx)
      end
    end
  end
end

return M
