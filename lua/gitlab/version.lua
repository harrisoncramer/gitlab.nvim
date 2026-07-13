local M = {}

local minimum_go_version = "1.25.1"

M.is_go_valid = function()
  local has_go, go = pcall(vim.system, { "go", "version" })
  if not has_go then
    return false
  end

  local go_version = vim.version.parse(go:wait().stdout, { strict = false })
  return go_version ~= nil and vim.version.ge(go_version, minimum_go_version)
end

M.check_go_version = function()
  local has_version = M.is_go_valid()
  if not has_version then
    return string.format(
      "Go is not installed, or version is older than %s. Please reinstall up-to-date Go version: https://go.dev/dl/",
      minimum_go_version
    )
  end
end

return M
