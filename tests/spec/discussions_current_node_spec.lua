-- The discussion buffers are shared between tabpages, so a tree can be displayed in more
-- than one window. Verifies that the node under the cursor is resolved from the window the
-- user is in, not from the first window that happens to show the buffer.

local NuiTree = require("nui.tree")
local common = require("gitlab.actions.common")
local tree_utils = require("gitlab.actions.discussions.tree")
local windows = require("gitlab.actions.discussions.windows")

---Render a two-note tree into a fresh buffer. Both notes are collapsed, so line 1 holds
---note "a" and line 2 note "b".
---@return NuiTree, integer bufnr
local function make_tree()
  local bufnr = vim.api.nvim_create_buf(false, true)
  local tree = NuiTree({
    bufnr = bufnr,
    nodes = {
      NuiTree.Node(
        { id = "a", text = "a", type = "note", is_root = true },
        { NuiTree.Node({ id = "a1", text = "a1", type = "note_body" }) }
      ),
      NuiTree.Node(
        { id = "b", text = "b", type = "note", is_root = true },
        { NuiTree.Node({ id = "b1", text = "b1", type = "note_body" }) }
      ),
    },
  })
  tree:render()
  return tree, bufnr
end

---Open a new tabpage showing `bufnr` with the cursor on `row`.
---@param bufnr integer
---@param row integer
---@return integer tabid, integer winid
local function open_in_new_tab(bufnr, row)
  vim.cmd("tabnew")
  local winid = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(winid, bufnr)
  vim.api.nvim_win_set_cursor(winid, { row, 0 })
  return vim.api.nvim_get_current_tabpage(), winid
end

describe("actions/common.get_current_node", function()
  after_each(function()
    vim.cmd("silent! tabonly")
  end)

  it("Reads the cursor of the current window, not of the first window showing the buffer", function()
    local tree, bufnr = make_tree()
    local first_tabid, _ = open_in_new_tab(bufnr, 1)
    local second_tabid, _ = open_in_new_tab(bufnr, 2)

    assert.are.equal("b", common.get_current_node(tree).text)

    vim.api.nvim_set_current_tabpage(first_tabid)
    assert.are.equal("a", common.get_current_node(tree).text)

    vim.api.nvim_set_current_tabpage(second_tabid)
    assert.are.equal("b", common.get_current_node(tree).text)
  end)

  it("Falls back to the registered discussion window of the current tabpage", function()
    local tree, bufnr = make_tree()
    open_in_new_tab(bufnr, 1)

    local tabid, winid = open_in_new_tab(bufnr, 2)
    windows.set(tabid, { winid = winid, bufnr = bufnr, view_type = "discussions" })
    -- Leave the tree window while staying in the same tabpage
    vim.cmd("split")
    vim.api.nvim_win_set_buf(0, vim.api.nvim_create_buf(false, true))

    assert.are.equal("b", common.get_current_node(tree).text)
    windows.remove(tabid)
  end)

  it("Returns nil when no window of the current tabpage shows the tree", function()
    local tree, bufnr = make_tree()
    open_in_new_tab(bufnr, 1)
    vim.cmd("tabnew")

    assert.is_nil(common.get_current_node(tree))
  end)
end)

describe("actions/discussions/tree.restore_cursor_position", function()
  after_each(function()
    vim.cmd("silent! tabonly")
  end)

  it("Clamps against the target window's buffer, not against the focused one", function()
    local tree, bufnr = make_tree()
    local _, winid = open_in_new_tab(bufnr, 1)

    -- Focus a window whose buffer is shorter than the tree. The rebuild restores cursors
    -- for every registered window, so this is the normal case, not an exotic one.
    vim.cmd("tabnew")
    vim.api.nvim_buf_set_lines(vim.api.nvim_get_current_buf(), 0, -1, false, { "one line" })

    tree_utils.restore_cursor_position(winid, tree, 0, tree:get_node("-b"), nil)

    assert.are.same({ 2, 0 }, vim.api.nvim_win_get_cursor(winid))
  end)
end)

describe("actions/discussions/tree.toggle_node", function()
  after_each(function()
    vim.cmd("silent! tabonly")
  end)

  it("Toggles the node under the given window's cursor while another tab shows the tree", function()
    local tree, bufnr = make_tree()
    open_in_new_tab(bufnr, 1)
    local _, winid = open_in_new_tab(bufnr, 2)

    tree_utils.toggle_node(winid, tree)

    assert.is_false(tree:get_node("-a"):is_expanded())
    assert.is_true(tree:get_node("-b"):is_expanded())
  end)
end)
