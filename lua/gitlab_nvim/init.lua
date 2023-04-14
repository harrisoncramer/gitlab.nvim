local Job = require("plenary.job")
local Popup = require("nui.popup")
local u = require("gitlab_nvim.utils")
local M = {}

M.PROJECT_ID = nil

local event = require("nui.utils.autocmd").event

local popup = Popup({
  buf_options = {
    filetype = 'gitlab_nvim'
  },
  enter = true,
  focusable = true,
  border = {
    style = "rounded",
    text = {
      top = "Comment",
    },
  },
  position = "50%",
  size = {
    width = "40%",
    height = "60%",
  },
})

M.popup = popup

vim.api.nvim_buf_get_lines(0, 0, -1, false)

M.comment = function()
  local relative_file_path = u.get_relative_file_path()
  local current_line_number = u.get_current_line_number()

  -- mount/open the component
  popup:mount()

  popup:on({ event.BufLeave }, function()
    local text = u.get_buffer_text(popup.bufnr)
    popup:unmount()
    Job:new({
      command = "/Users/harrisoncramer/Desktop/gitlab_nvim/bin",
      args = {
        "comment",
        M.PROJECT_ID,
        current_line_number,
        relative_file_path,
        text,
      },
      on_stdout = function(_, line)
        require("notify")(line, "info")
      end,
      on_stderr = function(_, line)
        require("notify")(line, "error")
      end,
      on_exit = function(code)
      end,
    }):start()
  end, { once = true })
end

M.projectInfo = function()
  local data = {}
  Job:new({
    command = "/Users/harrisoncramer/Desktop/gitlab_nvim/bin",
    args = { "projectInfo" },
    on_stdout = function(_, line)
      table.insert(data, line)
    end,
    on_stderr = function(_, line)
      print(line)
    end,
    on_exit = function()
      u.P(data)
    end,
  }):start()
end

M.setup = function(args)
  if args.project_id == nil then
    error("No project ID provided!")
  end
  M.PROJECT_ID = args.project_id
end

return M
