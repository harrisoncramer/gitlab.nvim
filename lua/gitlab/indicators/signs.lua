local u = require("gitlab.utils")
local state = require("gitlab.state")
local List = require("gitlab.utils.list")
local discussion_sign_name = require("gitlab.indicators.diagnostics").discussion_sign_name

local M = {}
M.clear_signs = function()
  vim.fn.sign_unplace(discussion_sign_name)
end

local gitlab_comment = "GitlabComment"
local gitlab_range = "GitlabRange"

local severity_map = {
  "Error",
  "Warn",
  "Info",
  "Hint",
}

---Refresh the discussion signs for currently loaded file in reviewer For convinience we use same
---string for sign name and sign group ( currently there is only one sign needed)
---@param diagnostics Diagnostic[]
---@param bufnr number
M.set_signs = function(diagnostics, bufnr)
  if not state.settings.discussion_signs.enabled then
    return
  end

  -- Filter diagnostics from the 'gitlab' source and apply custom signs
  for _, diagnostic in ipairs(diagnostics) do
    ---@type SignTable[]
    local existing_signs =
      vim.fn.sign_getplaced(vim.api.nvim_get_current_buf(), { group = discussion_sign_name })[1].signs

    if diagnostic.end_lnum then
      local linenr = diagnostic.lnum + 1
      while linenr <= diagnostic.end_lnum do
        linenr = linenr + 1
        local conflicting_comment_sign = List.new(existing_signs):find(function(sign)
          return u.ends_with(sign.name, gitlab_comment) and sign.lnum == linenr
        end)
        if conflicting_comment_sign == nil then
          vim.fn.sign_place(
            linenr,
            discussion_sign_name,
            "DiagnosticSign" .. M.severity .. gitlab_range,
            bufnr,
            { lnum = linenr, priority = state.settings.discussion_signs.priority }
          )
        end
      end
    end

    vim.fn.sign_place(
      diagnostic.lnum + 1,
      discussion_sign_name,
      "DiagnosticSign" .. M.severity .. gitlab_comment,
      bufnr,
      { lnum = diagnostic.lnum + 1, priority = state.settings.discussion_signs.priority }
    )

    -- TODO: Detect whether diagnostic is ranged and set helper signs
  end
end

---Define signs for discussions
M.setup_signs = function()
  local discussion_sign_settings = state.settings.discussion_signs
  local comment_icon = discussion_sign_settings.icons.comment
  local range_icon = discussion_sign_settings.icons.range
  M.severity = severity_map[state.settings.discussion_signs.severity]
  local signs = { "Error", "Warn", "Hint", "Info" }
  for _, type in ipairs(signs) do
    -- Define comment highlight group
    local hl = "DiagnosticSign" .. type
    local comment_hl = hl .. gitlab_comment
    vim.fn.sign_define(comment_hl, {
      text = comment_icon,
      texthl = comment_hl,
    })
    vim.cmd(string.format("highlight link %s %s", comment_hl, hl))

    -- Define range highlight group
    local range_hl = hl .. gitlab_range
    vim.fn.sign_define(range_hl, {
      text = range_icon,
      texthl = range_hl,
    })
    vim.cmd(string.format("highlight link %s %s", range_hl, hl))
  end
end

return M
