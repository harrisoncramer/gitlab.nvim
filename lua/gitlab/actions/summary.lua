-- This module is responsible for the MR description
-- This lets the user open the description in a popup and
-- send edits to the description back to Gitlab
local path             = require("plenary.path")
local Popup            = require("nui.popup")
local job              = require("gitlab.job")
local state            = require("gitlab.state")
local u                = require("gitlab.utils")
local M                = {}

local descriptionPopup = Popup(u.create_popup_state("Loading Description...", "80%", "80%"))

-- The function will render the MR description in a popup
M.summary              = function()
  descriptionPopup:mount()
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
    descriptionPopup.border:set_text("top", title, "center")
    state.set_popup_keymaps(descriptionPopup, M.edit_description, M.attach_file)
  end)
end

-- This function will PUT the new description to the Go server
M.edit_description     = function(text)
  local body = { description = text }
  job.run_job("/mr/description", "PUT", body, function(data)
    vim.notify(data.message, vim.log.levels.INFO)
    state.INFO.description = data.mr.description
  end)
end

M.attach_file          = function()
  local attachment_dir = state.settings.attachment_dir
  if not attachment_dir or attachment_dir == '' then
    vim.notify("Must provide image directory", vim.log.levels.ERROR)
    return
  end

  local files = u.list_files_in_folder(attachment_dir)

  if files == nil then
    vim.notify(string.format("Could not list files in %s", attachment_dir), vim.log.levels.ERROR)
    return
  end

  vim.ui.select(files, {
    prompt = 'Choose image',
  }, function(choice)
    if not choice then return end
    local full_path = attachment_dir .. (u.is_windows() and "\\" or "/") .. choice
    local body = { file_path = full_path, file_name = choice }
    job.run_job("/mr/description/image", "POST", body, function(data)
      local markdown = data.markdown
      local current_line = u.get_current_line_number()
      local bufnr = vim.api.nvim_get_current_buf()
      vim.api.nvim_buf_set_lines(bufnr, current_line - 1, current_line, false, { markdown })
    end)
  end)
end

return M
