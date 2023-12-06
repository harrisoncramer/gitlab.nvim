local M = {}
local state = require("gitlab.state")
local u = require("gitlab.utils")

---@param nodes Discussion[]|UnlinkedDiscussion[]
local get_data = function(nodes)
  local total_resolvable = 0
  local total_resolved = 0
  if nodes == vim.NIL then
    return ""
  end

  for _, d in ipairs(nodes) do
    local first_child = d.notes[1]
    if first_child ~= nil then
      if first_child.resolvable then
        total_resolvable = total_resolvable + 1
      end
      if first_child.resolved then
        total_resolved = total_resolved + 1
      end
    end
  end

  return total_resolvable, total_resolved
end

local function content(nodes, bufnr)
  local file_name = u.basename(vim.api.nvim_buf_get_name(bufnr))
  local resolvable, resolved = get_data(nodes)
  return state.settings.discussion_tree.winbar(file_name, resolvable, resolved)
end

---This function sends the edited comment to the Go server
---@param unlinked_bufnr integer
---@param linked_bufnr integer
---@param linked_discussions Discussion[]
---@param unlinked_discussions UnlinkedDiscussion[]
M.update_winbars = function(unlinked_bufnr, linked_bufnr, linked_discussions, unlinked_discussions)
  vim.api.nvim_buf_set_name(unlinked_bufnr, "Gitlab Notes")
  vim.api.nvim_buf_set_name(linked_bufnr, "Gitlab Discussions")

  local w1 = vim.fn.bufwinid(unlinked_bufnr)
  vim.wo[w1].winbar = content(unlinked_discussions, unlinked_bufnr)
  local w2 = vim.fn.bufwinid(linked_bufnr)
  vim.wo[w2].winbar = content(linked_discussions, linked_bufnr)
end

return M
