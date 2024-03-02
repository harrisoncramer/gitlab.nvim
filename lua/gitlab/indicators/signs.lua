local List = require("gitlab.utils.list")
local state = require("gitlab.state")
local common = require("gitlab.indicators.common")
local diffview_lib = require("diffview.lib")
local discussion_helper_sign_start = "gitlab_discussion_helper_start"
local discussion_helper_sign_mid = "gitlab_discussion_helper_mid"
local discussion_helper_sign_end = "gitlab_discussion_helper_end"

local M = {}
M.discussion_sign_name = "gitlab_discussion"

---Takes in a note and creates a sign to be placed in the reviewer
---@param note Note
---@return SignTable
local function create_sign(note)
  return {
    id = note.id,
    name = M.discussion_sign_name,
    group = M.discussion_sign_name,
    priority = state.settings.discussion_sign.priority,
    buffer = nil,
  }
end

---Takes in a list of discussions and turns them into a list of
---signs to be placed in the old SHA
---@param discussions Discussion[]
---@return SignTable[]
local function parse_old_signs_from_discussions(discussions)
  local view = diffview_lib.get_current_view()
  if not view then
    return {}
  end

  return List.new(discussions):filter(common.is_single_line):map(common.get_first_note):map(create_sign)
end

---Refresh the discussion signs for currently loaded file in reviewer For convinience we use same
---string for sign name and sign group ( currently there is only one sign needed)
---@param discussions Discussion[]
M.refresh_signs = function(discussions)
  local filtered_discussions = common.filter_placeable_discussions(discussions)
  local old_signs = parse_old_signs_from_discussions(filtered_discussions)
  if old_signs == nil then
    vim.notify("Could not parse old signs from discussions", vim.log.levels.ERROR)
    return
  end

  -- TODO: This is not working, the signs are not being placed
  vim.fn.sign_unplace(M.discussion_sign_name)
  vim.fn.sign_placelist(old_signs)
end

---Define signs for discussions if not already defined
M.setup_signs = function()
  local discussion_sign = state.settings.discussion_sign
  local signs = {
    [M.discussion_sign_name] = discussion_sign.text,
    [discussion_helper_sign_start] = discussion_sign.helper_signs.start,
    [discussion_helper_sign_mid] = discussion_sign.helper_signs.mid,
    [discussion_helper_sign_end] = discussion_sign.helper_signs["end"],
  }
  for sign_name, sign_text in pairs(signs) do
    if #vim.fn.sign_getdefined(sign_name) == 0 then
      vim.fn.sign_define(sign_name, {
        text = sign_text,
        linehl = discussion_sign.linehl,
        texthl = discussion_sign.texthl,
        culhl = discussion_sign.culhl,
        numhl = discussion_sign.numhl,
      })
    end
  end
end

-- Places a sign on the line for currently reviewed file.
---@param signs SignTable[] table of signs. See :h sign_placelist
---@param type string "new" if diagnostic should be in file after changes else "old"
M.place_sign = function(signs, type)
  local view = diffview_lib.get_current_view()
  if not view then
    return
  end
  if type == "new" then
    for _, sign in ipairs(signs) do
      sign.buffer = view.cur_layout.b.file.bufnr
    end
  elseif type == "old" then
    for _, sign in ipairs(signs) do
      sign.buffer = view.cur_layout.a.file.bufnr
    end
  end
  vim.fn.sign_placelist(signs)
end

-- Places signs in new SHA
---@param signs SignTable[] table of signs. See :h sign_placelist
M.place_signs_in_new_sha = function(signs, type)
  local view = diffview_lib.get_current_view()
  if not view then
    return
  end
  for _, sign in ipairs(signs) do
    sign.buffer = view.cur_layout.b.file.bufnr
  end
  vim.fn.sign_placelist(signs)
end

return M
