-- This module contains the logic responsible for building and starting
-- the Golang server. The Go server is responsible for making API calls
-- to Gitlab and returning the data
local state = require("gitlab.state")
local u     = require("gitlab.utils")
local M     = {}

-- Starts the Go server and call the callback provided
M.start     = function(callback)
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
M.build = function(override)
  local file_path = u.current_file_path()
  local parent_dir = vim.fn.fnamemodify(file_path, ":h:h:h:h")
  state.settings.bin_path = parent_dir
  state.settings.bin = parent_dir .. (u.is_windows() and "\\bin.exe" or "/bin")

  if not override then
    local binary_exists = vim.loop.fs_stat(state.settings.bin)
    if binary_exists ~= nil then return end
  end

  local cmd = u.is_windows() and
      'cd cmd && go build -o bin.exe && move bin.exe ..\\' or
      'cd cmd && go build -o bin && mv bin ../bin'

  local command = string.format(cmd, state.settings.bin_path)
  local null = u.is_windows() and " >NUL" or " > /dev/null"
  local installCode = os.execute(command .. null)
  if installCode ~= 0 then
    vim.notify("Could not install gitlab.nvim!", vim.log.levels.ERROR)
    return false
  end
  return true
end

return M
