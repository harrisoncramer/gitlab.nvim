local Popup = require("nui.popup")
local comment = Popup({
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

return comment
