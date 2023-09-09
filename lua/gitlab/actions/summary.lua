-- This module is responsible for the MR description
-- This lets the user open the description in a popup and
-- send edits to the description back to Gitlab
local Layout        = require("nui.layout")
local Popup         = require("nui.popup")
local job           = require("gitlab.job")
local u             = require("gitlab.utils")
local state         = require("gitlab.state")
local miscellaneous = require("gitlab.actions.miscellaneous")
local M             = {
  layout_visible = false,
  layout = nil,
  layout_buf = nil,
  title_bufnr = nil,
  description_bufnr = nil
}


-- The function will render the MR description in a popup
M.summary          = function()
  if M.layout_visible then
    M.layout:unmount()
    M.layout_visible = false
    return
  end

  local layout, title_popup, description_popup = M.create_layout()

  M.layout = layout
  M.layout_buf = layout.bufnr
  M.layout_visible = true

  local function exit()
    layout:unmount()
    M.layout_visible = false
  end

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
    vim.api.nvim_buf_set_lines(title_popup.bufnr, 0, -1, false, { title })
    state.set_popup_keymaps(description_popup, M.edit_summary, miscellaneous.attach_file, exit)
    state.set_popup_keymaps(title_popup, M.edit_summary, nil, exit)
  end)
end

-- This function will PUT the new description to the Go server
M.edit_summary     = function()
  local description = u.get_buffer_text(M.description_bufnr)
  local title = u.get_buffer_text(M.title_bufnr):gsub("\n", " ")
  local body = { title = title, description = description }
  job.run_job("/mr/summary", "PUT", body, function(data)
    vim.notify(data.message, vim.log.levels.INFO)
    state.INFO.description = data.mr.description
    state.INFO.title = data.mr.title
    M.layout:unmount()
    M.layout_visible = false
  end)
end

local top_popup    = {
  buf_options = {
    filetype = 'markdown'
  },
  focusable = true,
  border = {
    style = "rounded",
    text = {
      top = "Merge Request"
    },
  },
}

local bottom_popup = {
  buf_options = {
    filetype = 'markdown'
  },
  enter = true,
  focusable = true,
  border = {
    style = "rounded",
  },
}

M.create_layout    = function()
  local title_popup = Popup(top_popup)
  M.title_bufnr = title_popup.bufnr
  local description_popup = Popup(bottom_popup)
  M.description_bufnr = description_popup.bufnr

  local layout = Layout(
    {
      position = "50%",
      relative = "editor",
      size = {
        width = 100,
        height = 80,
      },
    },
    Layout.Box({
      Layout.Box(title_popup, { size = { height = 3 } }),
      Layout.Box(description_popup, { size = "50%" }),
    }, { dir = "col" })
  )

  layout:mount()

  return layout, title_popup, description_popup
end

return M
