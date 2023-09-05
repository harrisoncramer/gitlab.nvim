-- This Module contains all of the code specific to the Diffview reviewer.
local state           = require("gitlab.state")
local async_ok, async = pcall(require, "diffview.async")

local M               = {
  bufnr = nil,
  tabnr = nil
}

-- Public Functions
-- These functions are exposed externally and are used
-- when the reviewer is consumed by other code. They must follow the specification
-- outlined in the reviewer/init.lua file
M.open                = function()
  vim.api.nvim_command(string.format("DiffviewOpen %s", state.INFO.target_branch))
  M.tabnr = vim.api.nvim_get_current_tabpage()
end

M.jump                = function(file_name, new_line, old_line)
  if M.tabnr == nil then
    vim.notify("Can't jump to Diffvew. Is it open?", vim.log.levels.ERROR)
    return
  end
  vim.api.nvim_set_current_tabpage(M.tabnr)
  vim.cmd("DiffviewFocusFiles")
  local view = require("diffview.lib").get_current_view()
  if view == nil then
    vim.notify("Could not find Diffview view", vim.log.levels.ERROR)
    return
  end
  local files = view.panel:ordered_file_list()
  local layout = view.cur_layout
  for _, file in ipairs(files) do
    if file.path == file_name then
      if not async_ok then
        vim.notify("Could not load Diffview async", vim.log.levels.ERROR)
        return
      end
      async.await(view:set_file(file))
      if new_line ~= nil then
        layout.b:focus()
        vim.api.nvim_win_set_cursor(0, { tonumber(new_line), 0 })
      elseif old_line ~= nil then
        layout.a:focus()
        vim.api.nvim_win_set_cursor(0, { tonumber(old_line), 0 })
      end
      break
    end
  end
end

M.get_location        = function()
  if M.tabnr == nil then return nil, nil, "Diffview reviewer must be initialized first" end
  local bufnr = vim.api.nvim_get_current_buf()
  -- check if we are in the diffview tab
  local tabnr = vim.api.nvim_get_current_tabpage()
  if tabnr ~= M.tabnr then return nil, nil, "Line location can only be determined within reviewer window" end
  -- check if we are in the diffview buffer
  local view = require("diffview.lib").get_current_view()
  if view == nil then
    vim.notify("Could not find Diffview view", vim.log.levels.ERROR)
    return
  end
  local layout = view.cur_layout
  local file_name = nil
  local current_line_changes = nil
  if layout.a.file.bufnr == bufnr then
    file_name = layout.a.file.path
    current_line_changes = { new_line = nil, old_line = vim.api.nvim_win_get_cursor(0)[1] }
    return file_name, current_line_changes
  elseif layout.b.file.bufnr == bufnr then
    file_name = layout.b.file.path
    current_line_changes = { new_line = vim.api.nvim_win_get_cursor(0)[1], old_line = nil }
    return file_name, current_line_changes
  end
  return nil, nil, "Line location can only be determined within reviewer window"
end

return M
