local state = require("gitlab.state")
local u = require("gitlab.utils")
local job = require("gitlab.job")
local M = {}

M.attach_file = function()
  local attachment_dir = state.settings.attachment_dir
  if not attachment_dir or attachment_dir == "" then
    u.notify("Must provide valid attachment_dir in plugin setup", vim.log.levels.ERROR)
    return
  end

  local files = u.list_files_in_folder(attachment_dir)

  if files == nil then
    u.notify(string.format("Could not list files in %s", attachment_dir), vim.log.levels.ERROR)
    return
  end

  vim.ui.select(files, {
    prompt = "Choose attachment",
  }, function(choice)
    if not choice then
      return
    end
    local full_path = attachment_dir .. u.path_separator .. choice
    local body = { file_path = full_path, file_name = choice }
    job.run_job("/attachment", "POST", body, function(data)
      local markdown = data.markdown
      local current_line = u.get_current_line_number()
      local bufnr = vim.api.nvim_get_current_buf()
      vim.api.nvim_buf_set_lines(bufnr, current_line - 1, current_line, false, { markdown })
    end)
  end)
end

---Toggle the value in a "Boolean buffer"
M.toggle_bool = function()
  local bufnr = vim.api.nvim_get_current_buf()
  local current_val = u.get_buffer_text(bufnr)
  vim.schedule(function()
    u.switch_can_edit_buf(bufnr, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { u.toggle_string_bool(current_val) })
    u.switch_can_edit_buf(bufnr, false)
  end)
end

return M
