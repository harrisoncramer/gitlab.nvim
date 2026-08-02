-- Verifies the commit-history tab id is forgotten when its Diffview view closes, so the
-- browse gate never keeps pointing at a dead tabpage.

describe("reviewer.clear_history_tab", function()
  local reviewer = require("gitlab.reviewer")

  it("Clears history_tabid when the closed view's tab matches", function()
    reviewer.history_tabid = 42
    reviewer.clear_history_tab(42)
    assert.is_nil(reviewer.history_tabid)
  end)

  it("Keeps history_tabid when a different tab closes", function()
    reviewer.history_tabid = 42
    reviewer.clear_history_tab(7)
    assert.are.equal(42, reviewer.history_tabid)
  end)
end)
