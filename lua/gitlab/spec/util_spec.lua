describe("utils/init.lua", function()
  it("Loads package", function()
    local utils_ok, _ = pcall(require, "gitlab.utils")
    assert._is_true(utils_ok)
  end)

  describe("extract", function()
    it("Extracts a single value", function()
      local u = require("gitlab.utils")
      local t = { { one = 1, two = 2 }, { three = 3, four = 4 } }
      local got = u.extract(t, "one")
      local want = { 1 }
      assert.are.same(got, want)
    end)
    it("Returns nothing with empty table", function()
      local u = require("gitlab.utils")
      local t = {}
      local got = u.extract(t, "one")
      local want = {}
      assert.are.same(got, want)
    end)
  end)

  describe("get_last_word", function()
    it("Returns the last word in a sentence", function()
      local u = require("gitlab.utils")
      local sentence = "Hello world!"
      local got = u.get_last_word(sentence)
      local want = "world!"
      assert.True(got == want)
    end)
  end)
end)
