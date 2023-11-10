local state = require("gitlab.state")
local u = require("gitlab.utils")
local job = require("gitlab.job")
local M = {}

M.open_in_browser = function()
  local url = state.INFO.web_url
  if url == nil then
    u.notify("Could not get Gitlab URL", vim.log.levels.ERROR)
    return
  end
  if vim.fn.has("mac") == 1 then
    vim.fn.jobstart({ "open", url })
  elseif vim.fn.has("unix") == 1 then
    vim.fn.jobstart({ "xdg-open", url })
  else
    u.notify("Opening a Gitlab URL is not supported on this OS!", vim.log.levels.ERROR)
  end
end

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
    local full_path = attachment_dir .. (u.is_windows() and "\\" or "/") .. choice
    local body = { file_path = full_path, file_name = choice }
    job.run_job("/mr/attachment", "POST", body, function(data)
      local markdown = data.markdown
      local current_line = u.get_current_line_number()
      local bufnr = vim.api.nvim_get_current_buf()
      vim.api.nvim_buf_set_lines(bufnr, current_line - 1, current_line, false, { markdown })
    end)
  end)
end

return M
