local Layout = require("nui.layout")
local Popup = require("nui.popup")

local opts = {
	buf_options = {
		filetype = "markdown",
	},
	focusable = true,
	border = {
		style = "rounded",
	},
}

local title_popup = Popup(opts)
local description_popup = Popup(opts)
local info_popup = Popup(opts)

local layout = Layout(
	{
		position = "50%",
		relative = "editor",
		size = {
			width = "95%",
			height = "95%",
		},
	},
	Layout.Box({
		Layout.Box(title_popup, { size = { height = 3 } }),
		Layout.Box({
			Layout.Box(description_popup, { grow = 1 }),
			Layout.Box(info_popup, { size = { height = 15 } }),
		}, { dir = "col", size = "100%" }),
	}, { dir = "col" })
)

layout:mount()
