local M = {}

M.is_go_valid = function()
  local go_version = io.popen("go version"):read("*a")
  if go_version then
    local major, minor, _ = go_version:match("(%d+)%.(%d+)%.?(%d*)")
    if major and tonumber(major) >= 1 and tonumber(minor) >= 25 then
      return true
    else
      return false
    end
  else
    return false
  end
end

M.check_go_version = function()
  local has_version = M.is_go_valid()
  if not has_version then
    return "Go is not installed, or version is older than 1.25.1. Please reinstall up-to-date Go version: https://go.dev/dl/"
  end
end

return M
