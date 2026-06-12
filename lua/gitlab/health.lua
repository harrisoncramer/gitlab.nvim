local state = require("gitlab.state")
local List = require("gitlab.utils.list")
local version = require("gitlab.version")
local u = require("gitlab.utils")

local M = {}

---Check the health of the plugin.
---@param return_results boolean If false (e.g., when invoked by `:checkhealth gitlab`), the result is not returned and a health report is started instead
---@return boolean? success When return_results is false returns nil, otherwise returns true if the health ckeck doesn't find any issues, and false if there are errors
M.check = function(return_results)
  local warnings = List.new({})
  local errors = List.new({})

  if not return_results then
    vim.health.start("gitlab.nvim")
  end

  -- TODO: Remove state.settings.reviewer and add to `removed_settings_fields` - this warning has been here for two years...
  if state.settings.reviewer == "delta" then
    table.insert(
      warnings,
      "Delta is no longer a supported reviewer, please use diffview and update your setup function"
    )
  end

  local required_deps = {
    {
      name = "MunifTanjim/nui.nvim",
      package = "nui.popup",
    },
    {
      name = "dlyongemallo/diffview-plus.nvim",
      package = "diffview",
    },
  }

  local recommended_deps = {
    {
      name = "stevearc/dressing.nvim",
      package = "dressing",
    },
    {
      name = "nvim-tree/nvim-web-devicons",
      package = "nvim-web-devicons",
    },
    {
      name = "dlyongemallo/diffview-plus.nvim",
      package = "diffview.api",
    },
  }

  if state.settings.server.binary_provided then
    local binary_exists = vim.loop.fs_stat(state.settings.server.binary)
    if binary_exists == nil then
      table.insert(
        errors,
        string.format("The user-provided server path (%s) does not exist", state.settings.server.binary)
      )
    end
  else
    local go_version_problem = version.check_go_version()
    if go_version_problem ~= nil then
      table.insert(errors, go_version_problem)
    end
  end

  for _, dep in ipairs(required_deps) do
    local ok, _ = pcall(require, dep.package)
    if not ok then
      table.insert(errors, string.format("%s is a required dependency, but cannot be found", dep.name))
    end
  end

  for _, dep in ipairs(recommended_deps) do
    local ok, _ = pcall(require, dep.package)
    if not ok then
      table.insert(warnings, string.format("%s is a recommended dependency", dep.name))
    end
  end

  local removed_fields_in_user_config = {}
  local removed_settings_fields = {
    "dialogue",
    "discussion_tree.add_emoji",
    "discussion_tree.copy_node_url",
    "discussion_tree.delete_comment",
    "discussion_tree.delete_emoji",
    "discussion_tree.edit_comment",
    "discussion_tree.jump_to_file",
    "discussion_tree.jump_to_reviewer",
    "discussion_tree.open_in_browser",
    "discussion_tree.publish_draft",
    "discussion_tree.refresh_data",
    "discussion_tree.reply",
    "discussion_tree.switch_view",
    "discussion_tree.toggle_all_discussions",
    "discussion_tree.toggle_draft_mode",
    "discussion_tree.toggle_node",
    "discussion_tree.toggle_resolved",
    "discussion_tree.toggle_resolved_discussions",
    "discussion_tree.toggle_tree_type",
    "discussion_tree.toggle_unresolved_discussions",
    "help",
    "popup.keymaps.next_field",
    "popup.keymaps.prev_field",
    "popup.perform_action",
    "popup.perform_linewise_action",
    "review_pane", -- Only relevant for the Delta reviewer
  }

  for _, field in ipairs(removed_settings_fields) do
    if u.get_nested_field(state.settings, field) ~= nil then
      table.insert(removed_fields_in_user_config, field)
    end
  end

  if #removed_fields_in_user_config ~= 0 then
    table.insert(
      warnings,
      "The following settings fields have been removed:\n" .. table.concat(removed_fields_in_user_config, "\n")
    )
  end

  if #errors > 0 then
    for _, err in ipairs(errors) do
      vim.health.error(err)
    end
  end

  if #warnings > 0 then
    for _, err in ipairs(warnings) do
      vim.health.warn(err)
    end
  end

  if #warnings + #errors == 0 then
    vim.health.ok("Gitlab plugin is okay!")
  end

  if return_results then
    return #errors == 0
  end
end

return M
