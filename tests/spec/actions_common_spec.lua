local actions_common = require("gitlab.actions.common")

local sha = "3f454a98e586d1aa0d322e19afd5e67e08f2d3c8"

local function line_code(old_line, new_line)
  return sha .. "_" .. old_line .. "_" .. new_line
end

local function position(type, old_line, new_line, code)
  return { type = type, old_line = old_line, new_line = new_line, line_code = code or "" }
end

describe("gitlab/actions/common.lua", function()
  describe("get_line_numbers_for_range", function()
    describe("with line codes", function()
      it("Computes a range on the new SHA", function()
        local range = {
          start = position("new", 0, 40, line_code(1, 40)),
          ["end"] = position("new", 0, 44, line_code(1, 44)),
        }
        assert.are.same({ 40, 44, true }, { actions_common.get_line_numbers_for_range(nil, 44, range) })
      end)

      it("Computes a range on the old SHA", function()
        local range = {
          start = position("old", 10, 0, line_code(10, 20)),
          ["end"] = position("old", 12, 0, line_code(12, 20)),
        }
        assert.are.same({ 10, 12, false }, { actions_common.get_line_numbers_for_range(12, nil, range) })
      end)

      it("Computes a range spanning deleted and added lines", function()
        local range = {
          start = position("old", 5, 0, line_code(5, 38)),
          ["end"] = position("new", 0, 44, line_code(7, 44)),
        }
        assert.are.same({ 38, 44, true }, { actions_common.get_line_numbers_for_range(nil, 44, range) })
      end)
    end)

    describe("without line codes", function()
      it("Computes a range on the new SHA from the range's new lines", function()
        local range = {
          start = position("new", 0, 24),
          ["end"] = position("new", 0, 26),
        }
        assert.are.same({ 24, 26, true }, { actions_common.get_line_numbers_for_range(nil, 26, range) })
      end)

      it("Computes a range on the old SHA from the range's old lines", function()
        local range = {
          start = position("old", 10, 0),
          ["end"] = position("old", 12, 0),
        }
        assert.are.same({ 10, 12, false }, { actions_common.get_line_numbers_for_range(12, nil, range) })
      end)

      it("Computes a range from the range's lines when only one line code is empty", function()
        local range = {
          start = position("new", 0, 24, line_code(1, 24)),
          ["end"] = position("new", 0, 26),
        }
        assert.are.same({ 24, 26, true }, { actions_common.get_line_numbers_for_range(nil, 26, range) })
      end)

      it("Falls back to a single line for a range spanning deleted and added lines", function()
        local range = {
          start = position("old", 5, 0),
          ["end"] = position("new", 0, 44),
        }
        assert.are.same({ 44, 44, true }, { actions_common.get_line_numbers_for_range(nil, 44, range) })
      end)

      it("Falls back to a single line when the range's lines are missing", function()
        local range = {
          start = position("old", 5, nil),
          ["end"] = position("new", nil, 44),
        }
        assert.are.same({ 44, 44, true }, { actions_common.get_line_numbers_for_range(nil, 44, range) })
      end)
    end)
  end)
end)
