local discussions = require("gitlab.actions.discussions")
local windows = require("gitlab.actions.discussions.windows")
local draft_notes = require("gitlab.actions.draft_notes")
local winbar = require("gitlab.actions.discussions.winbar")
local diagnostics = require("gitlab.indicators.diagnostics")
local state = require("gitlab.state")
local u = require("gitlab.utils")

---@param id string
---@param note_id integer
local function make_discussion(id, note_id)
  return {
    id = id,
    individual_note = false,
    notes = {
      {
        id = note_id,
        author = { username = "author" },
        body = "Body of " .. id,
        created_at = "2023-10-28T18:27:34.082Z",
        position = vim.NIL,
        resolvable = false,
        resolved = false,
      },
    },
  }
end

---Open a tab with a diff buffer and the discussion tree, cursor in the diff buffer.
---@return integer tabid, integer diff_winid, integer diff_bufnr
local function open_tab_with_tree()
  vim.cmd("tabnew")
  local tabid = vim.api.nvim_get_current_tabpage()
  local diff_winid = vim.api.nvim_get_current_win()
  local diff_bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(diff_bufnr, 0, -1, false, { "one", "two", "three" })
  vim.api.nvim_win_set_buf(diff_winid, diff_bufnr)
  discussions.open()
  vim.api.nvim_set_current_win(diff_winid)
  return tabid, diff_winid, diff_bufnr
end

---Place one diagnostic per discussion id on `lnum` (1-based).
---@param bufnr integer
---@param lnum integer
---@param ids string[]
local function set_diagnostics(bufnr, lnum, ids)
  local ds = {}
  for _, id in ipairs(ids) do
    table.insert(ds, { lnum = lnum - 1, col = 0, message = "Note on " .. id, user_data = { discussion_id = id } })
  end
  vim.diagnostic.set(diagnostics.diagnostics_namespace, bufnr, ds)
end

describe("actions/discussions.move_to_discussion_tree", function()
  local original_rebuild_view, original_notify, original_select
  local notifications

  before_each(function()
    original_rebuild_view = draft_notes.rebuild_view
    draft_notes.rebuild_view = function() end
    original_notify = u.notify
    notifications = {}
    u.notify = function(msg)
      table.insert(notifications, msg)
    end
    original_select = vim.ui.select

    state.INFO = { web_url = "https://gitlab.example/-/merge_requests/1" }
    state.settings.discussion_tree.tree_type = "simple"
    state.DISCUSSION_DATA = {
      discussions = { make_discussion("disc-a", 101), make_discussion("disc-b", 102) },
      unlinked_discussions = {},
      emojis = {},
    }
  end)

  after_each(function()
    draft_notes.rebuild_view = original_rebuild_view
    u.notify = original_notify
    vim.ui.select = original_select
    vim.diagnostic.reset(diagnostics.diagnostics_namespace)
    vim.cmd("tabnew")
    vim.cmd("silent! tabonly")
    winbar.cleanup_timer()
    discussions.linked_bufnr = nil
    discussions.unlinked_bufnr = nil
    discussions.discussion_tree = nil
    discussions.unlinked_discussion_tree = nil
    state.DISCUSSION_DATA = nil
    state.INFO = nil
  end)

  it("Puts the cursor on the discussion of the only diagnostic on the line", function()
    local tabid, diff_winid, diff_bufnr = open_tab_with_tree()
    set_diagnostics(diff_bufnr, 2, { "disc-b" })
    vim.api.nvim_win_set_cursor(diff_winid, { 2, 0 })

    discussions.move_to_discussion_tree()

    local entry = windows.get(tabid)
    local _, line = discussions.discussion_tree:get_node("-disc-b")
    assert.are.equal(entry.winid, vim.api.nvim_get_current_win())
    assert.are.equal(line, vim.api.nvim_win_get_cursor(entry.winid)[1])
  end)

  it("Opens the discussion tree first when the tab has none", function()
    vim.cmd("tabnew")
    local tabid = vim.api.nvim_get_current_tabpage()
    local diff_bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(diff_bufnr, 0, -1, false, { "one", "two", "three" })
    vim.api.nvim_win_set_buf(0, diff_bufnr)
    set_diagnostics(diff_bufnr, 1, { "disc-a" })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })

    discussions.move_to_discussion_tree()

    local entry = windows.get(tabid)
    assert.is_not_nil(entry)
    local _, line = discussions.discussion_tree:get_node("-disc-a")
    assert.are.equal(entry.winid, vim.api.nvim_get_current_win())
    assert.are.equal(line, vim.api.nvim_win_get_cursor(entry.winid)[1])
  end)

  it("Lets the user choose when the line carries several diagnostics", function()
    local tabid, diff_winid, diff_bufnr = open_tab_with_tree()
    set_diagnostics(diff_bufnr, 3, { "disc-a", "disc-b" })
    vim.api.nvim_win_set_cursor(diff_winid, { 3, 0 })
    local offered = {}
    vim.ui.select = function(items, _, on_choice)
      for _, item in ipairs(items) do
        table.insert(offered, item.user_data.discussion_id)
      end
      on_choice(items[2])
    end

    discussions.move_to_discussion_tree()

    assert.are.same({ "disc-a", "disc-b" }, offered)
    local entry = windows.get(tabid)
    local _, line = discussions.discussion_tree:get_node("-disc-b")
    assert.are.equal(line, vim.api.nvim_win_get_cursor(entry.winid)[1])
  end)

  it("Stays put when the user aborts the choice", function()
    local _, diff_winid, diff_bufnr = open_tab_with_tree()
    set_diagnostics(diff_bufnr, 3, { "disc-a", "disc-b" })
    vim.api.nvim_win_set_cursor(diff_winid, { 3, 0 })
    vim.ui.select = function(_, _, on_choice)
      on_choice(nil)
    end

    discussions.move_to_discussion_tree()

    assert.are.equal(diff_winid, vim.api.nvim_get_current_win())
  end)

  it("Warns on a line without a diagnostic", function()
    state.settings.reviewer_settings.jump_with_no_diagnostics = false
    local _, diff_winid, diff_bufnr = open_tab_with_tree()
    set_diagnostics(diff_bufnr, 1, { "disc-a" })
    vim.api.nvim_win_set_cursor(diff_winid, { 2, 0 })

    discussions.move_to_discussion_tree()

    assert.are.equal(diff_winid, vim.api.nvim_get_current_win())
    assert.are.same({ "No diagnostics for this line." }, notifications)
  end)

  it("Jumps to the tree window's last position on a line without a diagnostic when enabled", function()
    state.settings.reviewer_settings.jump_with_no_diagnostics = true
    local tabid, diff_winid = open_tab_with_tree()
    local entry = windows.get(tabid)
    entry.last_row, entry.last_column = 2, 0

    vim.api.nvim_win_set_cursor(diff_winid, { 1, 0 })
    discussions.move_to_discussion_tree()

    assert.are.equal(entry.winid, vim.api.nvim_get_current_win())
    assert.are.equal(2, vim.api.nvim_win_get_cursor(entry.winid)[1])
    state.settings.reviewer_settings.jump_with_no_diagnostics = false
  end)
end)
