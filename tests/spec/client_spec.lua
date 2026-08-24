describe("gitlab/client.lua", function()
  describe("_make_on_exit", function()
    local notifications
    local client

    before_each(function()
      notifications = {}
      package.loaded["gitlab.utils"] = {
        notify = function(msg, level)
          table.insert(notifications, { msg = msg, level = level })
        end,
      }
      -- client.lua captures `u` via a top-level require, so stubbing gitlab.utils only
      -- takes effect if client.lua is required again after the stub is in place.
      package.loaded["gitlab.client"] = nil
      client = require("gitlab.client")
    end)

    after_each(function()
      package.loaded["gitlab.utils"] = nil
      package.loaded["gitlab.client"] = nil
    end)

    -- vim.schedule callbacks run on the next event-loop tick, so tests need to poll
    -- for a side effect instead of asserting immediately after calling the handler.
    local function wait_for(condition_fn)
      vim.wait(200, condition_fn, 10)
    end

    local function base_out()
      return { code = 0, signal = 0, stdout = "", stderr = "" }
    end

    describe("curl-level notices", function()
      it("does not notify when curl exits cleanly with no stderr", function()
        client._make_on_exit({ "curl" }, "/ping", nil, nil)(base_out())
        -- No side effect to poll for here: just let the scheduled callback run.
        vim.wait(50)
        assert.are.same({}, notifications)
      end)

      it("warns with the exit code when curl exits non-zero", function()
        local out = base_out()
        out.code = 3
        client._make_on_exit({ "curl" }, "/ping", nil, nil)(out)
        wait_for(function()
          return #notifications > 0
        end)
        assert.are.same(1, #notifications)
        assert.matches("exited with code 3", notifications[1].msg)
        assert.are.same(vim.log.levels.WARN, notifications[1].level)
      end)

      it("warns about the signal, not the code, when curl is killed", function()
        local out = base_out()
        out.code = 0
        out.signal = 9
        client._make_on_exit({ "curl" }, "/ping", nil, nil)(out)
        wait_for(function()
          return #notifications > 0
        end)
        assert.are.same(1, #notifications)
        assert.matches("killed by signal 9", notifications[1].msg)
        assert.is_nil(notifications[1].msg:match("exited with code"))
      end)

      it("warns with the command and trimmed stderr when curl writes to stderr", function()
        local out = base_out()
        out.stderr = "  some linker warning\n"
        client._make_on_exit({ "curl", "-s", "localhost:1234/ping" }, "/ping", nil, nil)(out)
        wait_for(function()
          return #notifications > 0
        end)
        assert.are.same(1, #notifications)
        assert.matches("curl %-s localhost:1234/ping", notifications[1].msg)
        assert.matches("some linker warning", notifications[1].msg)
        assert.are.same(vim.log.levels.WARN, notifications[1].level)
      end)
    end)

    describe("JSON decoding", function()
      it("treats an empty body as no usable data without notifying a decode failure", function()
        local seen_error_callback_calls = 0
        client._make_on_exit({ "curl" }, "/ping", nil, function()
          seen_error_callback_calls = seen_error_callback_calls + 1
        end)(base_out())
        wait_for(function()
          return seen_error_callback_calls > 0
        end)
        assert.are.same(1, seen_error_callback_calls)
        assert.are.same({}, notifications)
      end)

      it("reports error with the endpoint and decode error when the body is invalid JSON", function()
        local out = base_out()
        out.stdout = "not json"
        client._make_on_exit({ "curl" }, "/mr/info", nil, nil)(out)
        wait_for(function()
          return #notifications > 0
        end)
        assert.are.same(1, #notifications)
        assert.matches("Failed to parse JSON from /mr/info endpoint", notifications[1].msg)
        assert.matches("decode error:", notifications[1].msg)
        assert.are.same(vim.log.levels.ERROR, notifications[1].level)
      end)
    end)

    describe("dispatch outcomes", function()
      it("calls on_error_callback with no arguments when there is no usable data", function()
        local seen = "unset"
        client._make_on_exit({ "curl" }, "/ping", function()
          error("callback should not run")
        end, function(data)
          seen = data
        end)(base_out())
        wait_for(function()
          return seen == nil
        end)
        assert.is_nil(seen)
      end)

      it("notifies nothing when there is no usable data and no on_error_callback", function()
        client._make_on_exit({ "curl" }, "/ping", nil, nil)(base_out())
        -- No side effect to poll for here: just let the scheduled callback run.
        vim.wait(50)
        assert.are.same({}, notifications)
      end)

      it("calls on_error_callback with the full decoded data on an application-level error", function()
        local seen
        local out = base_out()
        out.stdout = vim.json.encode({ message = "Failed", details = "Gitlab Error" })
        client._make_on_exit({ "curl" }, "/ping", nil, function(data)
          seen = data
        end)(out)
        wait_for(function()
          return seen ~= nil
        end)
        assert.are.same("Failed", seen.message)
        assert.are.same("Gitlab Error", seen.details)
        assert.are.same({}, notifications)
      end)

      it("notifies message and details on an application-level error with no on_error_callback", function()
        local out = base_out()
        out.stdout = vim.json.encode({ message = "Failed", details = "Gitlab Error" })
        client._make_on_exit({ "curl" }, "/ping", nil, nil)(out)
        wait_for(function()
          return #notifications > 0
        end)
        assert.are.same(1, #notifications)
        assert.are.same("Failed: Gitlab Error", notifications[1].msg)
        assert.are.same(vim.log.levels.ERROR, notifications[1].level)
      end)

      it("calls callback with the decoded data on success", function()
        local seen
        local out = base_out()
        out.stdout = vim.json.encode({ message = "Done" })
        client._make_on_exit({ "curl" }, "/ping", function(data)
          seen = data
        end, function()
          error("on_error_callback should not run")
        end)(out)
        wait_for(function()
          return seen ~= nil
        end)
        assert.are.same("Done", seen.message)
        assert.are.same({}, notifications)
      end)

      it("notifies the message on success with no callback", function()
        local out = base_out()
        out.stdout = vim.json.encode({ message = "Done" })
        client._make_on_exit({ "curl" }, "/ping", nil, nil)(out)
        wait_for(function()
          return #notifications > 0
        end)
        assert.are.same(1, #notifications)
        assert.are.same("Done", notifications[1].msg)
        assert.are.same(vim.log.levels.INFO, notifications[1].level)
      end)
    end)
  end)
end)
