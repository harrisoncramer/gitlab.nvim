return {
  hello = function()
    local Job = require("plenary.job")
    -- async
    local data = {}
    Job:new({
      command = "/Users/harrisoncramer/Desktop/gitlab_nvim/bin",
      args = { "hi", "hi" },
      on_stdout = function(_, line)
        table.insert(data, line)
      end,
      on_exit = function()
        P(data)
      end,
    }):start()
  end,
}
