local state = require("gitlab.state")
local delta = require("gitlab.reviewer.delta")

local M = {
  reviewer = nil,
}

M.init = function()
  if state.settings.reviewer == "delta" then
    M.reviewer = delta
    return
  end

  -- We may support multiple reviewers in the future
  M.reviewer = delta

  -- Once the reviewer is chosen, map all the functions
  M.open = M.reviewer.open
  M.get_jump_location = M.reviewer.get_jump_location
  M.get_location = M.reviewer.get_location
  M.jump = M.reviewer.jump
end


return M
