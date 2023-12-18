-- This module is responsible for creating am MR
-- for the current branch
local Layout = require("nui.layout")
local Popup = require("nui.popup")
local job = require("gitlab.job")
local u = require("gitlab.utils")
local state = require("gitlab.state")
local miscellaneous = require("gitlab.actions.miscellaneous")

---@class Mr
---@field target? string
---@field title? string
---@field description? string

---@class Args
---@field target? string
---@field template_file? string

local M = {
  layout_visible = false,
  layout = nil,
  layout_buf = nil,
  title_bufnr = nil,
  description_bufnr = nil,
}

local title_popup_settings = {
  buf_options = {
    filetype = "markdown",
  },
  focusable = true,
  border = {
    style = "rounded",
  },
}

local target_popup_settings = {
  buf_options = {
    filetype = "markdown",
  },
  focusable = false,
  border = {
    style = "rounded",
    text = {
      top = "Target branch",
    },
  },
}

local description_popup_settings = {
  buf_options = {
    filetype = "markdown",
  },
  enter = true,
  focusable = true,
  border = {
    style = "rounded",
    text = {
      top = "Description",
    },
  },
}

-- 1. Get target branch
---@param args? Args
M.start = function(args)
  if not args then
    args = {}
  end
  if args.target ~= nil then
    M.pick_template({ target = args.target }, args)
    return
  end

  if state.settings.create_mr.target ~= nil then
    M.pick_template({ target = state.settings.create_mr.target }, args)
    return
  end

  local all_branch_names = u.get_all_git_branches()
  vim.ui.select(all_branch_names, {
    prompt = "Choose target branch for merge",
  }, function(choice)
    if choice then
      M.pick_template({ target = choice }, args)
    end
  end)
end

local function make_template_path(t)
  local abs_pwd = vim.fn.expand("%:p:h")
  return abs_pwd
    .. state.settings.file_separator
    .. ".gitlab"
    .. state.settings.file_separator
    .. "merge_request_templates"
    .. state.settings.file_separator
    .. t
end

-- 2. Pick template (if applicable)
---@param mr Mr
---@param args Args
M.pick_template = function(mr, args)
  if not args then
    args = {}
  end

  local template_file = args.template_file or state.settings.create_mr.template_file
  if template_file ~= nil then
    local description = u.read_file(make_template_path(template_file))
    M.add_title({ target = mr.target, description = description })
    return
  end

  local all_templates = u.list_files_in_folder(".gitlab" .. state.settings.file_separator .. "merge_request_templates")
  if all_templates == nil then
    M.add_title({ target = mr.target })
    return
  end

  vim.ui.select(u.merge({ "Blank Template" }, all_templates), {
    prompt = "Choose Template",
  }, function(choice)
    if choice then
      local description = u.read_file(make_template_path(choice))
      M.add_title({ target = mr.target, description = description })
    elseif choice == "Blank Template" then
      M.add_title({ target = mr.target })
    end
  end)
end

---3. Prompts the user for the title of the MR
---@param mr Mr
M.add_title = function(mr)
  vim.ui.input({ prompt = "MR Title" }, function(title)
    if title == nil then
      return
    end

    mr.title = title

    M.open_confirmation_popup(mr)
  end)
end

-- The function will render a popup containing the MR title and MR description, and
-- target branch. The title and description are editable.
---@param mr Mr
M.open_confirmation_popup = function(mr)
  if M.layout_visible then
    M.layout:unmount()
    M.layout_visible = false
    return
  end

  local layout, title_popup, description_popup, target_popup = M.create_layout()

  M.layout = layout
  M.layout_buf = layout.bufnr
  M.layout_visible = true

  local function exit()
    layout:unmount()
    M.layout_visible = false
  end

  local description_lines = mr.description and M.build_description_lines(mr.description) or { "" }

  vim.schedule(function()
    vim.api.nvim_buf_set_lines(description_popup.bufnr, 0, -1, false, description_lines)
    vim.api.nvim_buf_set_lines(title_popup.bufnr, 0, -1, false, { mr.title })

    if target_popup then
      vim.api.nvim_buf_set_lines(target_popup.bufnr, 0, -1, false, { mr.target })
      vim.api.nvim_set_option_value("modifiable", false, { buf = target_popup.bufnr })
      vim.api.nvim_set_option_value("readonly", false, { buf = target_popup.bufnr })
    end

    state.set_popup_keymaps(
      description_popup,
      M.create_mr,
      miscellaneous.attach_file,
      { cb = exit, action_before_close = true }
    )
    state.set_popup_keymaps(title_popup, M.create_mr, nil, { cb = exit, action_before_close = true })
    vim.api.nvim_set_current_buf(description_popup.bufnr)
  end)
end

-- Builds a lua list of strings that contain the MR description
M.build_description_lines = function(template_content)
  local description_lines = {}
  for line in template_content:gmatch("[^\n]+") do
    table.insert(description_lines, line)
    table.insert(description_lines, "")
  end

  return description_lines
end

---This function will POST the new MR to create it
M.create_mr = function()
  local description = u.get_buffer_text(M.description_bufnr)
  local title = u.get_buffer_text(M.title_bufnr):gsub("\n", " ")
  local target = u.get_buffer_text(M.target_bufnr):gsub("\n", " ")

  local body = {
    title = title,
    description = description,
    target_branch = target,
  }

  job.run_job("/create_mr", "POST", body, function(data)
    u.notify(data.message, vim.log.levels.INFO)
    M.layout:unmount()
    M.layout_visible = false
  end)
end

M.create_layout = function()
  local title_popup = Popup(title_popup_settings)
  M.title_bufnr = title_popup.bufnr
  local description_popup = Popup(description_popup_settings)
  M.description_bufnr = description_popup.bufnr
  local target_branch_popup = Popup(target_popup_settings)
  M.target_bufnr = target_branch_popup.bufnr

  local internal_layout
  internal_layout = Layout.Box({
    Layout.Box(title_popup, { size = 3 }),
    Layout.Box(description_popup, { grow = 1 }),
    Layout.Box(target_branch_popup, { size = 3 }),
  }, { dir = "col" })

  local layout = Layout({
    position = "50%",
    relative = "editor",
    size = {
      width = "95%",
      height = "95%",
    },
  }, internal_layout)

  layout:mount()

  return layout, title_popup, description_popup, target_branch_popup
end

return M
