---Initialize neovim to use lua modules from luarocks and prepare correct search paths for
---modules, neovim plugins and load busted frameworks.

local modules = {
  "lua_modules/share/lua/5.1",
  "tests/plugins/diffview.nvim/lua",
  "tests/plugins/nui.nvim/lua",
  "tests/plugins/plenary.nvim/lua",
}
local lua_path_extensions = { "/?.lua", "/?/init.lua" }

local path = ""
for _, module_path in ipairs(modules) do
  for _, lua_path_extension in ipairs(lua_path_extensions) do
    path = path .. module_path .. lua_path_extension .. ";"
  end
end

package.path = path .. package.path
package.cpath = "lua_modules/lib/lua/5.1/?.so;" .. package.cpath
local k, l, _ = pcall(require, "luarocks.loader")
_ = k and l.add_context("busted", "$BUSTED_VERSION")

-- Initialize required plugins which needs it
require("diffview").setup()
