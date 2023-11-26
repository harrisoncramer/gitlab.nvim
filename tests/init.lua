---Initialize neovim to use lua modules from luarocks and prepare correct search paths for
---modules, neovim plugins and load busted frameworks.
local current_dir = vim.fn.getcwd() .. "/"
local modules = {
  "lua",
  "tests/plugins/diffview.nvim/lua",
  "tests/plugins/nui.nvim/lua",
  "tests/plugins/plenary.nvim/lua",
  "lua_modules/share/lua/5.1",
}
local lua_path_extensions = { "/?.lua", "/?/init.lua" }

local path = ""
for _, module_path in ipairs(modules) do
  for _, lua_path_extension in ipairs(lua_path_extensions) do
    path = path .. current_dir .. module_path .. lua_path_extension .. ";"
  end
end

package.path = path .. package.path
package.cpath = "lua_modules/lib/lua/5.1/?.so;" .. "lua_modules/lib/lua/5.1/?/init.so;" .. package.cpath

-- Initialize required plugins which needs it
require("diffview").setup()

-- Run busted -
require("busted.runner")({ standalone = false })
os.exit(0)
