local u = require("gitlab.utils")
local popup = require("gitlab.popup")
local Popup = require("nui.popup")
local state = require("gitlab.state")
local job = require("gitlab.job")
local reviewer = require("gitlab.reviewer")

local M = {}

local function create_squash_message_popup()
  return Popup(popup.create_popup_state("Squash Commit Message", state.settings.popup.squash_message))
end

---@class MergeOpts
---@field delete_branch boolean?
---@field squash boolean?
---@field squash_message string?

---@param opts MergeOpts
M.merge = function(opts)
  local merge_body = { squash = state.INFO.squash, delete_branch = state.INFO.delete_branch }
  if opts then
    merge_body.squash = opts.squash ~= nil and opts.squash
    merge_body.delete_branch = opts.delete_branch ~= nil and opts.delete_branch
  end

  if state.INFO.detailed_merge_status ~= "mergeable" then
    u.notify(string.format("MR not mergeable, currently '%s'", state.INFO.detailed_merge_status), vim.log.levels.ERROR)
    return
  end

  if merge_body.squash then
    local squash_message_popup = create_squash_message_popup()
    popup.set_up_autocommands(squash_message_popup, nil, vim.api.nvim_get_current_win())
    squash_message_popup:mount()
    popup.set_popup_keymaps(squash_message_popup, function(text)
      M.confirm_merge(merge_body, text)
    end, nil, popup.editable_popup_opts)
  else
    M.confirm_merge(merge_body)
  end
end

---@param merge_body MergeOpts
---@param squash_message string?
M.confirm_merge = function(merge_body, squash_message)
  if squash_message ~= nil then
    merge_body.squash_message = squash_message
  end

  job.run_job("/mr/merge", "POST", merge_body, function(data)
    reviewer.close()
    u.notify(data.message, vim.log.levels.INFO)
  end)
end

return M
