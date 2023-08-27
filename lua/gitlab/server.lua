-- This module contains the logic responsible for building and starting
-- the Golang server. The Go server is responsible for making API calls
-- to Gitlab and returning the data
local job      = require("gitlab.job")
local state    = require("gitlab.state")
local u        = require("gitlab.utils")
local M        = {}

-- Starts the Go server and call the callback provided
M.start_server = function(callback)
  local command = state.settings.bin
      .. " "
      .. state.settings.project_id
      .. " "
      .. state.settings.gitlab_url
      .. " "
      .. state.settings.port
      .. " "
      .. state.settings.auth_token
      .. " "
      .. state.settings.log_path

  vim.fn.jobstart(command, {
    on_stdout = function(job_id)
      if job_id <= 0 then
        vim.notify("Could not start gitlab.nvim binary", vim.log.levels.ERROR)
      else
        callback()
      end
    end,
    on_stderr = function(_, errors)
      local err_msg = ''
      for _, err in ipairs(errors) do
        if err ~= "" and err ~= nil then
          err_msg = err_msg .. err .. "\n"
        end
      end

      if err_msg ~= '' then vim.notify(err_msg, vim.log.levels.ERROR) end
    end
  })
end


-- Builds the Go binary
M.build = function()
  if not u.has_delta() then
    vim.notify("Please install delta to use gitlab.nvim!", vim.log.levels.ERROR)
    return
  end

  local file_path = u.current_file_path()
  local parent_dir = vim.fn.fnamemodify(file_path, ":h:h:h:h")
  state.settings.bin_path = parent_dir
  state.settings.bin = parent_dir .. "/bin"

  local binary_exists = vim.loop.fs_stat(state.settings.bin)
  if binary_exists ~= nil then return end

  local command = string.format("cd %s && make", state.settings.bin_path)
  local installCode = os.execute(command .. "> /dev/null")
  if installCode ~= 0 then
    vim.notify("Could not install gitlab.nvim!", vim.log.levels.ERROR)
    return false
  end
  return true
end

return M
