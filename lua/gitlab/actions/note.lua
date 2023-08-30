-- This module is responsible for creating new notes.
-- Notes are like comments but are not tied to specific
-- lines of code
local Popup           = require("nui.popup")
local state           = require("gitlab.state")
local job             = require("gitlab.job")
local u               = require("gitlab.utils")
local reviewer        = require("gitlab.reviewer")
local M               = {}

local note_popup      = Popup(u.create_popup_state("Note", "40%", "60%"))

-- This function will open a note popup in order to create a note on the changed/updated line in the current MR
M.create_note         = function()
  note_popup:mount()
  state.set_popup_keymaps(note_popup, function(text)
    M.confirm_create_note(text)
  end)
end

-- This function (settings.popup.perform_action) will send the note to the Go server
M.confirm_create_note = function(text)
  local jsonTable = { note = text }
  P(jsonTable)
  local json = vim.json.encode(jsonTable)
  job.run_job("/note", "POST", json, function(data)
    vim.notify("Note created")
  end)
end

return M
