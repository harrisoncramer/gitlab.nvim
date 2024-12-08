-- This module is responsible for creating am MR
-- for the current branch
local Layout = require("nui.layout")
local Input = require("nui.input")
local Popup = require("nui.popup")
local job = require("gitlab.job")
local u = require("gitlab.utils")
local popup = require("gitlab.popup")
local git = require("gitlab.git")
local state = require("gitlab.state")
local common = require("gitlab.actions.common")
local miscellaneous = require("gitlab.actions.miscellaneous")

---@class Mr
---@field target? string
---@field title? string
---@field description? string
---@field forked_project_id number?
---@field template_file? string
---@field delete_branch boolean?
---@field squash boolean?

local M = {
  started = false,
  layout_visible = false,
  layout = nil,
  layout_buf = nil,
  title_bufnr = nil,
  description_bufnr = nil,
  mr = {
    target = "",
    title = "",
    description = "",
    forked_project_id = state.settings.create_mr.fork.enabled and state.settings.create_mr.fork.forked_project_id
      or nil,
  },
}

M.reset_state = function()
  M.started = false
  M.mr.title = ""
  M.mr.target = ""
  M.mr.description = ""
  M.mr.forked_project_id = nil
end

---1. If the user has already begun writing an MR, prompt them to
--- continue working on it.
---@param args? Mr
M.start = function(args)
  if not git.check_current_branch_up_to_date_on_remote(vim.log.levels.ERROR) then
    return
  end

  if M.started then
    vim.ui.select({ "Yes", "No" }, { prompt = "Continue your previous MR?" }, function(choice)
      if choice == "Yes" then
        M.open_confirmation_popup(M.mr)
        return
      else
        M.reset_state()
        M.pick_target(args)
      end
    end)
  else
    M.pick_target(args)
  end
end

---2. Pick the target branch
---@param mr? Mr
M.pick_target = function(mr)
  if not mr then
    mr = {}
  end
  if mr.target ~= nil then
    M.pick_template(mr)
    return
  end

  if state.settings.create_mr.target ~= nil then
    mr.target = state.settings.create_mr.target
    M.pick_template(mr)
    return
  end

  -- Select target branch interactively if it hasn't been selected by other means
  u.select_target_branch(function(target)
    mr.target = target
    M.pick_template(mr)
  end)
end

local function make_template_path(t)
  local base_dir, err = git.base_dir()
  if err ~= nil then
    return
  end
  return base_dir
    .. state.settings.file_separator
    .. ".gitlab"
    .. state.settings.file_separator
    .. "merge_request_templates"
    .. state.settings.file_separator
    .. t
end

---3. Pick template (if applicable). This is used as the description
---@param mr Mr
M.pick_template = function(mr)
  if mr.description ~= nil then
    M.add_title(mr)
    return
  end

  local template_file = mr.template_file or state.settings.create_mr.template_file
  if template_file ~= nil then
    mr.description = u.read_file(make_template_path(template_file))
    M.add_title(mr)
    return
  end

  local all_templates = u.list_files_in_folder(".gitlab" .. state.settings.file_separator .. "merge_request_templates")
  if all_templates == nil then
    M.add_title(mr)
    return
  end

  local opts = { "Blank Template" }
  for _, v in ipairs(all_templates) do
    table.insert(opts, v)
  end
  vim.ui.select(opts, {
    prompt = "Choose Template",
  }, function(choice)
    if choice and choice ~= "Blank Template" then
      mr.description = u.read_file(make_template_path(choice))
    end
    M.add_title(mr)
  end)
end

---4. Prompts the user for the title of the MR
---@param mr Mr
M.add_title = function(mr)
  if mr.title ~= nil then
    M.open_confirmation_popup(mr)
    return
  end

  local input = Input({
    position = "50%",
    relative = "editor",
    size = state.settings.create_mr.title_input.width,
    border = {
      style = state.settings.create_mr.title_input.border,
      text = {
        top = "Title",
      },
    },
  }, {
    prompt = "",
    default_value = "",
    on_close = function() end,
    on_submit = function()
      if state.settings.create_mr.fork.enabled and state.settings.create_mr.fork.forked_project_id == nil then
        M.open_fork_popup(mr)
      else
        M.open_confirmation_popup(mr)
      end
    end,
    on_change = function(value)
      mr.title = value
    end,
  })
  input:mount()
end

---Sets the ID of the base project when working from a fork
---@param mr Mr
M.open_fork_popup = function(mr)
  local input = Input({
    position = "50%",
    relative = "editor",
    size = state.settings.create_mr.title_input.width,
    border = {
      style = state.settings.create_mr.title_input.border,
      text = {
        top = "Forked Project ID",
      },
    },
  }, {
    prompt = "",
    default_value = "",
    on_close = function() end,
    on_submit = function()
      M.open_confirmation_popup(mr)
    end,
    on_change = function(value)
      mr.forked_project_id = tonumber(value)
    end,
  })
  input:mount()
end

---5. Show the final popup.
---The function will render a popup containing the MR title and MR description,
---target branch, and the "delete_branch" and "squash" options. All fields are editable.
---@param mr Mr
M.open_confirmation_popup = function(mr)
  M.started = true
  if M.layout_visible then
    M.layout:unmount()
    M.layout_visible = false
    return
  end

  local layout, title_popup, description_popup, target_popup, delete_branch_popup, squash_popup, forked_project_id_popup =
    M.create_layout()

  local popups = {
    title_popup,
    description_popup,
    delete_branch_popup,
    squash_popup,
    target_popup,
  }

  if state.settings.create_mr.fork.enabled then
    table.insert(popups, 3, forked_project_id_popup)
  end

  M.layout = layout
  M.layout_buf = layout.bufnr
  M.layout_visible = true

  local function exit()
    local title = vim.fn.trim(u.get_buffer_text(M.title_bufnr))
    local description = u.get_buffer_text(M.description_bufnr)
    local target = vim.fn.trim(u.get_buffer_text(M.target_bufnr))
    local delete_branch = u.string_to_bool(u.get_buffer_text(M.delete_branch_bufnr))
    local squash = u.string_to_bool(u.get_buffer_text(M.squash_bufnr))
    local forked_project_id = tonumber(u.get_buffer_text(M.forked_project_id_bufnr))
    M.mr = {
      title = title,
      description = description,
      target = target,
      delete_branch = delete_branch,
      squash = squash,
      forked_project_id = forked_project_id,
    }
    layout:unmount()
    M.layout_visible = false
  end

  local description_lines = mr.description and common.build_content(mr.description) or { "" }
  local delete_branch = u.get_first_non_nil_value({ mr.delete_branch, state.settings.create_mr.delete_branch })
  local squash = u.get_first_non_nil_value({ mr.squash, state.settings.create_mr.squash })

  vim.schedule(function()
    vim.api.nvim_buf_set_lines(M.description_bufnr, 0, -1, false, description_lines)
    vim.api.nvim_buf_set_lines(M.title_bufnr, 0, -1, false, { mr.title })
    vim.api.nvim_buf_set_lines(M.target_bufnr, 0, -1, false, { mr.target })
    vim.api.nvim_buf_set_lines(M.delete_branch_bufnr, 0, -1, false, { u.bool_to_string(delete_branch) })
    vim.api.nvim_buf_set_lines(M.squash_bufnr, 0, -1, false, { u.bool_to_string(squash) })
    if state.settings.create_mr.fork.enabled then
      local forked_id = state.settings.create_mr.fork.forked_project_id or mr.forked_project_id
      vim.api.nvim_buf_set_lines(M.forked_project_id_bufnr, 0, -1, false, { tostring(forked_id) })
    end

    u.switch_can_edit_buf(M.delete_branch_bufnr, false)
    u.switch_can_edit_buf(M.squash_bufnr, false)
    u.switch_can_edit_buf(M.target_bufnr, false)

    local popup_opts = {
      cb = exit,
      action_before_close = true,
      action_before_exit = true,
    }

    popup.set_popup_keymaps(description_popup, M.create_mr, miscellaneous.attach_file, popup_opts)
    popup.set_popup_keymaps(title_popup, M.create_mr, nil, popup_opts)
    popup.set_popup_keymaps(target_popup, M.create_mr, M.select_new_target, popup_opts)
    popup.set_popup_keymaps(delete_branch_popup, M.create_mr, miscellaneous.toggle_bool, popup_opts)
    popup.set_popup_keymaps(squash_popup, M.create_mr, miscellaneous.toggle_bool, popup_opts)
    popup.set_popup_keymaps(forked_project_id_popup, M.create_mr, nil, popup_opts)
    popup.set_cycle_popups_keymaps(popups)

    vim.api.nvim_set_current_buf(M.description_bufnr)
  end)
end

---Prompts for interactive selection of a new target among remote-tracking branches
M.select_new_target = function()
  local bufnr = vim.api.nvim_get_current_buf()
  u.select_target_branch(function(target)
    vim.schedule(function()
      u.switch_can_edit_buf(bufnr, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { target })
      u.switch_can_edit_buf(bufnr, false)
    end)
  end)
end

---This function will POST the new MR to create it
M.create_mr = function()
  local description = u.get_buffer_text(M.description_bufnr)
  local title = u.get_buffer_text(M.title_bufnr):gsub("\n", " ")
  local target = u.get_buffer_text(M.target_bufnr):gsub("\n", " ")
  local delete_branch = u.string_to_bool(u.get_buffer_text(M.delete_branch_bufnr))
  local squash = u.string_to_bool(u.get_buffer_text(M.squash_bufnr))
  local forked_project_id = tonumber(u.get_buffer_text(M.forked_project_id_bufnr))

  local body = {
    title = title,
    description = description,
    target_branch = target,
    delete_branch = delete_branch,
    squash = squash,
    forked_project_id = forked_project_id,
  }

  job.run_job("/create_mr", "POST", body, function(data)
    u.notify(data.message, vim.log.levels.INFO)
    M.reset_state()
    M.layout:unmount()
    M.layout_visible = false
  end)
end

M.create_layout = function()
  local settings = u.merge(state.settings.popup, state.settings.popup.create_mr or {})
  local title_popup = Popup(popup.create_box_popup_state("Title", false, settings))
  M.title_bufnr = title_popup.bufnr
  local description_popup = Popup(popup.create_popup_state("Description", settings))
  M.description_bufnr = description_popup.bufnr
  local target_branch_popup = Popup(popup.create_box_popup_state("Target branch", false, settings))
  M.target_bufnr = target_branch_popup.bufnr
  local delete_title = vim.o.columns > 110 and "Delete source branch" or "Delete source"
  local delete_branch_popup = Popup(popup.create_box_popup_state(delete_title, false, settings))
  M.delete_branch_bufnr = delete_branch_popup.bufnr
  local squash_title = vim.o.columns > 110 and "Squash commits" or "Squash"
  local squash_popup = Popup(popup.create_box_popup_state(squash_title, false, settings))
  M.squash_bufnr = squash_popup.bufnr
  local forked_project_id_popup = Popup(popup.create_box_popup_state("Forked Project ID", false, settings))
  M.forked_project_id_bufnr = forked_project_id_popup.bufnr

  local boxes = {}
  if state.settings.create_mr.fork.enabled then
    table.insert(boxes, Layout.Box(forked_project_id_popup, { size = { width = 20 } }))
  end
  table.insert(boxes, Layout.Box(delete_branch_popup, { size = { width = #delete_title + 4 } }))
  table.insert(boxes, Layout.Box(squash_popup, { size = { width = #squash_title + 4 } }))
  table.insert(boxes, Layout.Box(target_branch_popup, { grow = 1 }))

  local internal_layout = Layout.Box({
    Layout.Box({
      Layout.Box(title_popup, { grow = 1 }),
    }, { size = 3 }),
    Layout.Box(description_popup, { grow = 1 }),
    Layout.Box(boxes, { size = 3 }),
  }, { dir = "col" })

  local layout = Layout({
    position = settings.position,
    relative = "editor",
    size = {
      width = settings.width,
      height = settings.height,
    },
  }, internal_layout)

  popup.set_up_autocommands(description_popup, layout, vim.api.nvim_get_current_win())

  layout:mount()

  return layout,
    title_popup,
    description_popup,
    target_branch_popup,
    delete_branch_popup,
    squash_popup,
    forked_project_id_popup
end

return M
