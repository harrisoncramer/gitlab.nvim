local job         = require("gitlab.job")
local state       = require("gitlab.state")
local M           = {}

M.assign_reviewer = function()
  vim.ui.select(state.PROJECT_MEMBERS, {
    prompt = 'Choose Reviewer',
    format_item = function(user)
      return user.username .. " (" .. user.name .. ")"
    end
  }, function(choice)
    if not choice then return end
    local json = vim.json.encode({ id = choice.id })
    job.run_job("mr/reviewer", "PUT", json)
  end)
end

M.remove_reviewer = function()
end

return M
