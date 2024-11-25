local state = require("gitlab.state")
local reviewer = require("gitlab.reviewer")
local git = require("gitlab.git")
local u = require("gitlab.utils")
local M = {}

---@class ChooseMergeRequestOptions
---@field open_reviewer? boolean
---@field label? string[]
---@field notlabel? string[]

---Opens up a select menu that lets you choose a different merge request.
---@param opts ChooseMergeRequestOptions|nil
M.choose_merge_request = function(opts)
  if opts == nil then
    opts = state.settings.choose_merge_request
  end

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

    if choice.source_branch ~= git.get_current_branch() then
      local has_clean_tree, clean_tree_err = git.has_clean_tree()
      if clean_tree_err ~= nil then
        return
      elseif not has_clean_tree then
        u.notify(
          "Cannot switch branch when working tree has changes, please stash or commit and push",
          vim.log.levels.ERROR
        )
        return
      end
    end

    vim.schedule(function()
      local _, branch_switch_err = git.switch_branch(choice.source_branch)
      if branch_switch_err ~= nil then
        return
      end

      vim.schedule(function()
        state.chosen_mr_iid = choice.iid
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
