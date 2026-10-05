-- The `draft_notes` API leaves `line_code` empty inside `line_range`, so resolving the
-- range from line codes alone makes a draft note's multi-line comment fail with
-- "attempt to perform arithmetic on local 'new_end_line' (a nil value)".

local common = require("gitlab.actions.common")

describe("actions/common.get_line_numbers_for_range", function()
  it("Resolves a NEW SHA range from its line codes", function()
    local start_line, end_line, is_new_sha = common.get_line_numbers_for_range(
      nil,
      500,
      { line_code = "a0185ee7c1543c5d1e2eee6bd336fcbf59504f38_482_495", type = "new" },
      { line_code = "a0185ee7c1543c5d1e2eee6bd336fcbf59504f38_487_500", type = "new" }
    )

    assert.are.same({ 495, 500, true }, { start_line, end_line, is_new_sha })
  end)

  it("Resolves an OLD SHA range from its line codes", function()
    local start_line, end_line, is_new_sha = common.get_line_numbers_for_range(
      487,
      nil,
      { line_code = "a0185ee7c1543c5d1e2eee6bd336fcbf59504f38_482_495", type = "old" },
      { line_code = "a0185ee7c1543c5d1e2eee6bd336fcbf59504f38_487_500", type = "old" }
    )

    assert.are.same({ 482, 487, false }, { start_line, end_line, is_new_sha })
  end)

  it("Falls back to the line numbers a draft note's range carries itself", function()
    local start_line, end_line, is_new_sha = common.get_line_numbers_for_range(
      nil,
      500,
      { line_code = "", new_line = 495, type = "new" },
      { line_code = "", new_line = 500, type = "new" }
    )

    assert.are.same({ 495, 500, true }, { start_line, end_line, is_new_sha })
  end)
end)
