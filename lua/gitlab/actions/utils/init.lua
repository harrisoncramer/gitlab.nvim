local u = require("gitlab.utils")
local state = require("gitlab.state")
local M = {}

---Build note header from note
---@param note Note
---@return string
M.build_note_header = function(note)
  return "@" .. note.author.username .. " " .. u.time_since(note.created_at)
end

---Build note header from draft note
---@return string
M.build_draft_note_header = function()
  if not state.USER then
    return ""
  end
  return " Draft note from @" .. state.USER.username
end

M.switch_can_edit_bufs = function(bool, ...)
  local bufnrs = { ... }
  ---@param v integer
  for _, v in ipairs(bufnrs) do
    u.switch_can_edit_buf(v, bool)
    vim.api.nvim_set_option_value("filetype", "gitlab", { buf = v })
  end
end

---@class TitleArg
---@field bufnr integer
---@field title string
---@field data table

---@param title_args TitleArg[]
M.add_empty_titles = function(title_args)
  for _, v in ipairs(title_args) do
    M.switch_can_edit_bufs(true, v.bufnr)
    local ns_id = vim.api.nvim_create_namespace("GitlabNamespace")
    vim.cmd("highlight default TitleHighlight guifg=#787878")

    vim.print(v)

    -- Set empty title if applicable
    if type(v.data) ~= "table" or #v.data == 0 then
      vim.api.nvim_buf_set_lines(v.bufnr, 0, 1, false, { v.title })
      local linnr = 1
      vim.api.nvim_buf_set_extmark(
        v.bufnr,
        ns_id,
        linnr - 1,
        0,
        { end_row = linnr - 1, end_col = string.len(v.title), hl_group = "TitleHighlight" }
      )
    end
  end
end

return M
