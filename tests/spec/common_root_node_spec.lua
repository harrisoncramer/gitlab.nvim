-- Without the nil-parent guard this test does not fail, it hangs, and the suite stops here.

local NuiTree = require("nui.tree")
local common = require("gitlab.actions.common")

describe("actions/common.get_root_node", function()
  it("Gives up on a top level node that is not marked as a root", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    local tree = NuiTree({
      bufnr = bufnr,
      nodes = { NuiTree.Node({ id = "a", text = "a", type = "note" }) },
    })
    tree:render()
    -- The loop only forms if NuiTree can answer `get_node(nil)`, which it does from the
    -- cursor of a window showing the buffer.
    vim.api.nvim_win_set_buf(0, bufnr)

    assert.is_nil(
      common.get_root_node(tree, tree:get_node("-a")),
      "get_root_node claimed a root for a note node that has no parent"
    )

    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)
end)
