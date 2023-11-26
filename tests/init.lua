---Initialize neovim to use lua modules from luarocks and prepare correct search paths for
---modules, neovim plugins and load busted frameworks.

local function build_path(modules, extensions)
  local path = ""
  for _, module_path in ipairs(modules) do
    for _, lua_path_extension in ipairs(extensions) do
      path = path .. module_path .. lua_path_extension .. ";"
    end
  end
  return path
end

local plugins_folder = "tests/plugins/*/lua"
local luarocks_cmd = "luarocks config --scope project"

-- Project path
local modules = { "lua" }
-- External plugins - dependencies
for plugin_path in vim.fn.glob(plugins_folder):gmatch("[^\r\n]+") do
  table.insert(modules, plugin_path)
end
-- Lua modules path
table.insert(modules, vim.fn.trim(vim.fn.system(luarocks_cmd .. " deploy_lua_dir")))

local lua_path_extensions = { "/?.lua", "/?/init.lua" }
package.path = build_path(modules, lua_path_extensions) .. package.path

local cmodules = {
  vim.fn.trim(vim.fn.system(luarocks_cmd .. " deploy_lib_dir")),
}
local lua_lib_extensions = { "/?.so", "/?/init.so" }
package.cpath = build_path(cmodules, lua_lib_extensions) .. package.cpath

-- Initialize required plugins which needs it
require("diffview").setup()

-- Run busted -
require("busted.runner")({ standalone = false })
os.exit(0)
