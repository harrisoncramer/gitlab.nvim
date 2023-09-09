-- This Module will pick the reviewer set in the user's
-- settings and then map all of it's functions
local state = require("gitlab.state")
local delta = require("gitlab.reviewer.delta")
local diffview = require("gitlab.reviewer.diffview")

local M = {
  reviewer = nil,
}

local reviewer_map = {
  delta = delta,
  diffview = diffview
}


M.init = function()
  local reviewer = reviewer_map[state.settings.reviewer]
  if reviewer == nil then
    vim.notify(string.format("gitlab.nvim could not find reviewer %s", state.settings.reviewer), vim.log.levels.ERROR)
    return
  end

  -- Opens the reviewer window. If either branch is out of date,
  -- prompts the user to pull down, then opens the reviewer
  M.open = function()
    local branch = vim.fn.system({ "git", "rev-parse", "--abbrev-ref", "HEAD" }):gsub("%s+", "")
    if branch == "main" or branch == "master" then
      return -- Must run reviews on feature branches
    end

    local target_not_ready, source_not_ready, err = M.ready_to_review(state.INFO.source_branch)
    if err then
      vim.notify(err, vim.log.levels.ERROR)
      return
    end

    if target_not_ready or source_not_ready then
      local opts = {
        string.format("Yes, pull \"%s\" and/or \"%s\"", state.INFO.source_branch, state.INFO.target_branch), "No, cancel" }
      vim.ui.select(opts, {
        prompt =
        'Your local repository is out-of-date. Pull branches?',
      }, function(choice)
        if not choice or choice == "No, cancel" then return end
        if target_not_ready then
          vim.fn.system({ "git", "pull", "--no-edit", "--no-rebase", "--ff-only", "origin", state.INFO.target_branch })
          if vim.v.shell_error ~= 0 then
            vim.notify(string.format("Could not pull %s branch", state.INFO.target_branch), vim.log.levels.ERROR)
            return
          end
        end
        if source_not_ready then
          vim.fn.system({ "git", "pull", "--no-edit", "--no-rebase", "--ff-only", "origin", state.INFO.source_branch })
          if vim.v.shell_error ~= 0 then
            vim.notify(string.format("Could not pull %s branch", state.INFO.source_branch), vim.log.levels.ERROR)
            return
          end
        end

        reviewer.open()
      end)
    else
      reviewer.open()
    end
  end

  M.jump = reviewer.jump
  -- Jumps to the location provided in the reviewer window
  -- Parameters:
  --   • {file_name}      The name of the file to jump to
  --   • {new_line}  The new_line of the change
  --   • {interval}  The old_line of the change

  M.get_location = reviewer.get_location
  -- Returns the current location (based on cursor) from the reviewer window in format:
  -- file_name, {new_line, old_line}, error
end

M.ready_to_review = function()
  vim.fn.system({ "git", "fetch" })
  if vim.v.shell_error ~= 0 then
    return nil, nil, "Could not fetch remote changes"
  end

  local target_output = vim.fn.system({ "git", "rev-list",
    string.format("%s..origin/%s", state.INFO.target_branch, state.INFO.target_branch) })
  if vim.v.shell_error ~= 0 then
    return nil, nil, string.format("Error checking status of %s branch", state.INFO.target_branch)
  end

  local source_output = vim.fn.system({ "git", "rev-list",
    string.format("%s..origin/%s", state.INFO.source_branch, state.INFO.source_branch) })
  if vim.v.shell_error ~= 0 then
    return nil, nil, string.format("Error checking status of %s branch", state.INFO.source_branch)
  end

  if target_output ~= "" or source_output ~= "" then
    return target_output ~= "", source_output ~= "", nil
  end

  return nil, nil, nil
end

return M
