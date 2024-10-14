describe("utils/init.lua", function()
  it("Loads package", function()
    local utils_ok, _ = pcall(require, "gitlab.utils")
    assert._is_true(utils_ok)
  end)

  local _, u = pcall(require, "gitlab.utils")
  describe("extract", function()
    it("Extracts a single value", function()
      local t = { { one = 1, two = 2 }, { three = 3, four = 4 } }
      local got = u.extract(t, "one")
      local want = { 1 }
      assert.are.same(want, got)
    end)
    it("Returns nothing with empty table", function()
      local t = {}
      local got = u.extract(t, "one")
      local want = {}
      assert.are.same(want, got)
    end)
  end)

  describe("get_last_word", function()
    it("Returns the last word in a sentence", function()
      local sentence = "Hello world!"
      local got = u.get_last_word(sentence)
      local want = "world!"
      assert.are.same(want, got)
    end)
    it("Returns an empty string without text", function()
      local sentence = ""
      local got = u.get_last_word(sentence)
      local want = ""
      assert.are.same(want, got)
    end)
    it("Returns whole string w/out divider", function()
      local sentence = "Thisdoesnothavebreaks"
      local got = u.get_last_word(sentence)
      assert.are.same(sentence, got)
    end)
    it("Returns correct word w/ different divider", function()
      local sentence = "this|uses|a|different|divider"
      local got = u.get_last_word(sentence, "|")
      local want = "divider"
      assert.are.same(want, got)
    end)
  end)

  describe("format_date", function()
    local current_date = {
      day = 19,
      hour = 22,
      isdst = false,
      min = 0,
      month = 11,
      sec = 44,
      wday = 1,
      yday = 323,
      year = 2023,
    }
    it("Returns days since a valid UTC timestamp", function()
      local stamp = "2023-11-16T19:52:36.946Z"
      local got = u.time_since(stamp, current_date)
      local want = "3 days ago"
      assert.are.same(want, got)
    end)

    it("Returns hours since a valid UTC timestamp", function()
      local stamp = "2023-11-19T19:52:36.946Z"
      local got = u.time_since(stamp, current_date)
      local want = "2 hours ago"
      assert.are.same(want, got)
    end)
    it("Returns readable time if > 1 year", function()
      local stamp = "2011-11-19T19:52:36.946Z"
      local got = u.time_since(stamp, current_date)
      local want = "November 19, 2011"
      assert.are.same(want, got)
    end)

    it("Parses TZ w/out offset (relative)", function()
      local stamp = "2023-11-14T18:44:02Z"
      local got = u.time_since(stamp, current_date)
      local want = "5 days ago"
      assert.are.same(want, got)
    end)
  end)

  describe("remove_first_value", function()
    it("Removes the first value correctly", function()
      local got = u.remove_first_value({ 1, 2 })
      local want = { 2 }
      assert.are.same(want, got)
    end)
    it("Handles a one-length list", function()
      local got = u.remove_first_value({ 1 })
      local want = {}
      assert.are.same(want, got)
    end)
    it("Handles a zero-length list", function()
      local got = u.remove_first_value({})
      local want = {}
      assert.are.same(want, got)
    end)
  end)

  describe("table_size", function()
    it("Works for associative tables", function()
      local got = u.remove_first_value({ 1, 2 })
      local want = { 2 }
      assert.are.same(want, got)
    end)
    it("Handles a one-length list", function()
      local got = u.remove_first_value({ 1 })
      local want = {}
      assert.are.same(want, got)
    end)
    it("Handles a zero-length list", function()
      local got = u.remove_first_value({})
      local want = {}
      assert.are.same(want, got)
    end)
  end)

  describe("contains", function()
    it("Finds a value in a list", function()
      local got = u.contains({ 1, 2 }, 1)
      assert._is_true(got)
    end)
    it("Handles missing values", function()
      local got = u.contains({ 1, 3, 4 }, 2)
      assert._is_false(got)
    end)
    it("Handles empty lists", function()
      local got = u.contains({}, 1)
      assert._is_false(got)
    end)
  end)

  describe("reverse", function()
    it("Reverses the values in a list", function()
      local got = u.reverse({ 1, 2, 3, 4 })
      local want = { 4, 3, 2, 1 }
      assert.are.same(got, want)
    end)
    it("Handles single value", function()
      local got = u.reverse({ 1 })
      local want = { 1 }
      assert.are.same(got, want)
    end)
    it("Handles empty list", function()
      local got = u.reverse({})
      local want = {}
      assert.are.same(got, want)
    end)
  end)

  describe("spread", function()
    it("Spreads the values", function()
      local t1 = { 1, 2, 3 }
      local t2 = { 4, 5, 6 }
      local got = u.spread(t1, t2)
      local want = { 1, 2, 3, 4, 5, 6 }
      assert.are.same(got, want)
    end)
    it("Handles an empty t1 table", function()
      local t1 = {}
      local t2 = { 4, 5, 6 }
      local got = u.spread(t1, t2)
      local want = { 4, 5, 6 }
      assert.are.same(got, want)
    end)
    it("Handles an empty t2 table", function()
      local t1 = { 1, 2, 3 }
      local t2 = {}
      local got = u.spread(t1, t2)
      local want = { 1, 2, 3 }
      assert.are.same(got, want)
    end)
    it("Handles both empty tables", function()
      local t1 = {}
      local t2 = {}
      local got = u.spread(t1, t2)
      local want = {}
      assert.are.same(got, want)
    end)
  end)

  describe("offset_to_seconds", function()
    local tests = {
      est = { "-0500", -18000 },
      pst = { "-0800", -28800 },
      gmt = { "+0000", 0 },
      cet = { "+0100", 360 },
      jst = { "+0900", 32400 },
      ist = { "+0530", 19800 },
      art = { "-0300", -10800 },
      aest = { "+1100", 39600 },
      mmt = { "+0630", 23400 },
    }

    for _, val in ipairs(tests) do
      local got = u.offset_to_seconds(val[1])
      local want = val[2]
      assert.are.same(got, want)
    end
  end)

  describe("format_to_local", function()
    local tests = {
      { "2023-10-28T16:25:09.482Z", "-0500", "10/28/2023 at 11:25" },
      { "2016-11-22T1:25:09.482Z", "-0500", "11/21/2016 at 20:25" },
      { "2016-11-22T1:25:09.482Z", "-0000", "11/22/2016 at 01:25" },
      { "2017-3-22T13:25:09.482Z", "+0700", "03/22/2017 at 20:25" },
      { "2023-10-28T11:25:09.482-05:00", "-0500", "10/28/2023 at 11:25" },
      { "2016-11-21T20:25:09.482-05:00", "-0500", "11/21/2016 at 20:25" },
      { "2016-11-22T1:25:09.482-00:00", "-0000", "11/22/2016 at 01:25" },
      { "2017-3-22T20:25:09.482+07:00", "+0700", "03/22/2017 at 20:25" },
      { "2016-11-22T1:25:09Z", "-0000", "11/22/2016 at 01:25" },
    }
    for _, val in ipairs(tests) do
      local got = u.format_to_local(val[1], val[2])
      local want = val[3]
      assert.are.same(got, want)
    end
  end)
end)
