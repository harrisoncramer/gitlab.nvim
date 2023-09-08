local state = require("gitlab.state")
local M = {}

M.open_in_browser = function()
  local url = state.INFO.web_url
  if url == nil then
    vim.notify("Could not get Gitlab URL", vim.log.levels.ERROR)
    return
  end
  if vim.fn.has("mac") == 1 then
    vim.fn.jobstart({ "open", url })
  elseif vim.fn.has("unix") == 1 then
    vim.fn.jobstart({ "xdg-open", url })
  else
    vim.notify("Opening a Gitlab URL is not supported on this OS!", vim.log.levels.ERROR)
  end
end

return M
