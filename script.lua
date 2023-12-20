local u = require("gitlab.utils")

local res = u.parse_hunk_headers("README.md", "main")
vim.print(res)
