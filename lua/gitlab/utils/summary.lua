local Popup = require("nui.popup")
local summary = Popup({
  buf_options = {
    filetype = 'markdown'
  },
  enter = true,
  focusable = true,
  border = {
    style = "rounded",
    text = {
      top = "Loading Summary...",
    },
  },
  position = "50%",
  size = {
    width = "80%",
    height = "80%",
  },
})

return summary
