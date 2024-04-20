local state = require("gitlab.state")
local reviewer = require("gitlab.reviewer")
local git = require("gitlab.git")
local u = require("gitlab.utils")
local M = {}

---@class SwitchOpts
---@field open_reviewer boolean

---Opens up a select menu that lets you choose a different merge request.
---@param opts SwitchOpts|nil
M.choose_merge_request = function(opts)
  if not git.has_clean_tree() then
    u.notify("Your local branch has changes, please stash or commit and push", vim.log.levels.ERROR)
    return
  end

  if opts == nil then
    opts = state.settings.choose_merge_request
  end

  vim.ui.select(state.MERGE_REQUESTS, {
    prompt = "Choose Merge Request",
    format_item = function(mr)
      return string.format("%s (%s)", mr.title, mr.author.name)
    end,
  }, function(choice)
    if not choice then
      return
    end

    if reviewer.is_open then
      reviewer.close()
    end

    vim.schedule(function()
      local err = git.switch_branch(choice.source_branch)
      if err ~= "" then
        u.notify(err, vim.log.levels.ERROR)
        return
      end

      vim.schedule(function()
        require("gitlab.server").restart(function()
          if opts.open_reviewer then
            require("gitlab").review()
          end
        end)
      end)
    end)
  end)
end

return M
