local indicators_common = require("gitlab.indicators.common")

local sha = "3f454a98e586d1aa0d322e19afd5e67e08f2d3c8"

describe("gitlab/indicators/common.lua", function()
  describe("parse_line_code", function()
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
end)
