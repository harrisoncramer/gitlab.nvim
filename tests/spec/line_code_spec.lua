local indicators_common = require("gitlab.indicators.common")
local actions_common = require("gitlab.actions.common")

local sha = "3f454a98e586d1aa0d322e19afd5e67e08f2d3c8"

describe("indicators/common.parse_line_code", function()
  it("Parses both line numbers", function()
    assert.are.same({ 10, 44 }, { indicators_common.parse_line_code(sha .. "_10_44") })
  end)

  it("Returns nil for an empty line code", function()
    assert.are.same({ nil, nil }, { indicators_common.parse_line_code("") })
  end)

  it("Returns nil for a missing line code", function()
    assert.are.same({ nil, nil }, { indicators_common.parse_line_code(nil) })
  end)
end)

describe("actions/common.get_line_numbers_for_range", function()
  it("Computes a range on the new SHA", function()
    assert.are.same(
      { 40, 44, true },
      { actions_common.get_line_numbers_for_range(nil, 44, sha .. "_1_40", sha .. "_1_44") }
    )
  end)

  it("Falls back to a single line on the new SHA when the line codes are empty", function()
    assert.are.same({ 26, 26, true }, { actions_common.get_line_numbers_for_range(nil, 26, "", "") })
  end)

  it("Falls back to a single line on the old SHA when the line codes are empty", function()
    assert.are.same({ 12, 12, false }, { actions_common.get_line_numbers_for_range(12, nil, "", "") })
  end)
end)
