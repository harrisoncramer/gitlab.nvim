local job = require("gitlab.job")

local M = {}

M.merge_requests_by_username = function(username)
  local body = { username = username }
  job.run_job("/merge_requests_by_username", "POST", body, function(data)
    local markdown = data.markdown
    local current_line = u.get_current_line_number()
    local bufnr = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(bufnr, current_line - 1, current_line, false, { markdown })
  end)
end

return M
