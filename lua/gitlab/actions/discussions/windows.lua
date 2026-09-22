-- Registry of the discussion window per tabpage. Several tabs (e.g. the MR diff and the
-- commit browser) can each show their own discussion tree, and the window in a given tab
-- may hold different buffers over time (linked/unlinked discussions, notes), so the split
-- state can't live in a single module-level handle.

local M = {}

---@class DiscussionWindowEntry
---@field split NuiSplit
---@field winid integer
---@field bufnr integer The buffer currently shown in `split`
---@field view_type "discussions"|"notes"
---@field last_row integer?
---@field last_column integer?
---@field last_node_at_cursor NuiTree.Node?

---@type table<integer, DiscussionWindowEntry>
local entries = {}

---@param tabid integer
---@param entry DiscussionWindowEntry?
---@return boolean
local function is_valid(tabid, entry)
  return entry ~= nil
    and vim.api.nvim_tabpage_is_valid(tabid)
    and vim.api.nvim_win_is_valid(entry.winid)
    -- A live window is not necessarily still this tab's window: `<C-w>T` moves it into a
    -- new tabpage, after which the entry would send `tabid` to a window somewhere else.
    and vim.api.nvim_win_get_tabpage(entry.winid) == tabid
end

---@param tabid integer
---@param entry DiscussionWindowEntry
M.set = function(tabid, entry)
  entries[tabid] = entry
end

---Get the entry for `tabid` (default: the current tabpage), or nil if there is none or it
---no longer points at a live tab/window.
---@param tabid integer?
---@return DiscussionWindowEntry?
M.get = function(tabid)
  tabid = tabid or vim.api.nvim_get_current_tabpage()
  local entry = entries[tabid]
  if not is_valid(tabid, entry) then
    entries[tabid] = nil
    return nil
  end
  return entry
end

---@param tabid integer
M.remove = function(tabid)
  entries[tabid] = nil
end

---@param winid integer
M.remove_by_winid = function(winid)
  for tabid, entry in pairs(entries) do
    if entry.winid == winid then
      entries[tabid] = nil
      return
    end
  end
end

---Call `fn(entry, tabid)` for every entry whose tab and window are still live, pruning the
---rest.
---@param fn fun(entry: DiscussionWindowEntry, tabid: integer)
M.each = function(fn)
  for tabid, entry in pairs(entries) do
    if is_valid(tabid, entry) then
      fn(entry, tabid)
    else
      entries[tabid] = nil
    end
  end
end

---@return boolean
M.any = function()
  local found = false
  M.each(function()
    found = true
  end)
  return found
end

return M
