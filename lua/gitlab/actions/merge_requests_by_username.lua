local job = require("gitlab.job")
local state = require("gitlab.state")
local reviewer = require("gitlab.reviewer")

local M = {}

M.merge_requests_by_username = function(username)
  local body = { username = username }
  job.run_job("/merge_requests_by_username", "POST", body, function(data)
    vim.ui.select(state.MERGE_REQUESTS, {
      prompt = "Choose Merge Request",
      format_item = function(mr)
        return string.format("%s [%s -> %s] (%s)", mr.title, mr.source_branch, mr.target_branch, mr.author.name)
      end,
    }, function(choice)
      if not choice then
        return
      end

      if reviewer.is_open then
        reviewer.close()
      end

      vim.schedule(function()
        local _, branch_switch_err = git.switch_branch(choice.source_branch)
        if branch_switch_err ~= nil then
          return
        end

        vim.schedule(function()
          state.chosen_target_branch = choice.target_branch
          require("gitlab.server").restart(function()
            if opts.open_reviewer then
              require("gitlab").review()
            end
          end)
        end)
      end)
    end)
    vim.print(data)
    -- local markdown = data.markdown
    -- local current_line = u.get_current_line_number()
    -- local bufnr = vim.api.nvim_get_current_buf()
    -- vim.api.nvim_buf_set_lines(bufnr, current_line - 1, current_line, false, { markdown })
  end)
end

return M
