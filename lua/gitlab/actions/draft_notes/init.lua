-- This module is responsible for CRUD operations for the draft notes in the discussion tree.
-- That includes things like editing existing draft notes in the tree, and
-- and deleting them. Normal notes and comments are managed separately,
-- under lua/gitlab/actions/discussions/init.lua
local common = require("gitlab.actions.common")
local discussion_tree = require("gitlab.actions.discussions.tree")
local job = require("gitlab.job")
local NuiTree = require("nui.tree")
local List = require("gitlab.utils.list")
local u = require("gitlab.utils")
local state = require("gitlab.state")

local M = {}

---Re-fetches all draft notes (and non-draft notes) and re-renders the relevant views
---@param unlinked boolean
---@param all boolean|nil
M.rebuild_view = function(unlinked, all)
  M.load_draft_notes(function()
    local discussions = require("gitlab.actions.discussions")
    discussions.rebuild_view(unlinked, all)
  end)
end

---Makes API call to get the discussion data, stores it in the state, and calls the callback
---@param callback function|nil
M.load_draft_notes = function(callback)
  state.discussion_tree.last_updated = nil
  state.load_new_state("draft_notes", function()
    if callback ~= nil then
      callback()
    end
  end)
end

---Will actually send the edits to Gitlab and refresh the draft_notes tree
---@param note_id integer
---@param unlinked boolean
---@return function
M.confirm_edit_draft_note = function(note_id, unlinked)
  return function(text)
    local all_notes = List.new(state.DRAFT_NOTES)
    local the_note = all_notes:find(function(note)
      return note.id == note_id
    end)
    local body = { note = text, position = the_note.position }
    job.run_job(string.format("/mr/draft_notes/%d", note_id), "PATCH", body, function(data)
      u.notify(data.message, vim.log.levels.INFO)
      M.rebuild_view(unlinked)
    end)
  end
end

---This function will actually send the deletion to Gitlab when you make a selection, and re-render the tree
---@param note_id integer
---@param unlinked boolean
M.confirm_delete_draft_note = function(note_id, unlinked)
  job.run_job(string.format("/mr/draft_notes/%d", note_id), "DELETE", nil, function(data)
    u.notify(data.message, vim.log.levels.INFO)
    M.rebuild_view(unlinked)
  end)
end

-- This function will trigger a popup prompting you to publish the current draft comment
M.publish_draft = function(tree)
  vim.ui.select({ "Confirm", "Cancel" }, {
    prompt = "Publish current draft comment?",
  }, function(choice)
    if choice == "Confirm" then
      M.confirm_publish_draft(tree)
    end
  end)
end

-- This function will trigger a popup prompting you to publish all draft notes
M.publish_all_drafts = function()
  vim.ui.select({ "Confirm", "Cancel" }, {
    prompt = "Publish all drafts?",
  }, function(choice)
    if choice == "Confirm" then
      M.confirm_publish_all_drafts()
    end
  end)
end

---Publishes all draft notes and comments. Re-renders all discussion views.
M.confirm_publish_all_drafts = function()
  local body = { publish_all = true }
  job.run_job("/mr/draft_notes/publish", "POST", body, function(data)
    u.notify(data.message, vim.log.levels.INFO)
    state.DRAFT_NOTES = {}
    local discussions = require("gitlab.actions.discussions")
    discussions.rebuild_view(false, true)
  end)
end

---Publishes the current draft note that is being hovered over in the tree,
---and then makes an API call to refresh the relevant data for that tree
---and re-render it.
---@param tree NuiTree
M.confirm_publish_draft = function(tree)
  local current_node = tree:get_node()
  local note_node = common.get_note_node(tree, current_node)
  local root_node = common.get_root_node(tree, current_node)

  if note_node == nil or root_node == nil then
    u.notify("Could not get note or root node", vim.log.levels.ERROR)
    return
  end

  ---@type integer
  local note_id = note_node.is_root and root_node.id or note_node.id
  local body = { note = note_id }
  job.run_job("/mr/draft_notes/publish", "POST", body, function(data)
    u.notify(data.message, vim.log.levels.INFO)

    local discussions = require("gitlab.actions.discussions")
    local unlinked = tree.bufnr == discussions.unlinked_bufnr
    M.rebuild_view(unlinked)
  end)
end

--- Helper functions
---Tells whether a draft note was left on a particular diff or is an unlinked note
---@param note DraftNote
M.has_position = function(note)
  return note.position.new_path ~= nil or note.position.old_path ~= nil
end

---Builds a note for the discussion tree for draft notes that are roots
---of their own discussions, e.g. not replies
---@param note DraftNote
---@return NuiTree.Node
M.build_root_draft_note = function(note)
  local _, root_text, root_text_nodes = discussion_tree.build_note(note)
  return NuiTree.Node({
    range = (type(note.position) == "table" and note.position.line_range or nil),
    text = root_text,
    type = "note",
    is_root = true,
    is_draft = true,
    id = note.id,
    root_note_id = note.id,
    file_name = (type(note.position) == "table" and note.position.new_path or nil),
    new_line = (type(note.position) == "table" and note.position.new_line or nil),
    old_line = (type(note.position) == "table" and note.position.old_line or nil),
    resolvable = false,
    resolved = false,
    url = state.INFO.web_url .. "#note_" .. note.id,
  }, root_text_nodes)
end

---Returns a list of nodes to add to the discussion tree. Can filter and return only unlinked (note) nodes.
---@param unlinked boolean
---@return NuiTree.Node[]
M.add_draft_notes_to_table = function(unlinked)
  local draft_notes = List.new(state.DRAFT_NOTES)
  local draft_note_nodes = draft_notes
    ---@param note DraftNote
    :filter(function(note)
      if unlinked then
        return not M.has_position(note)
      end
      return M.has_position(note)
    end)
    :filter(function(note)
      return note.discussion_id == "" -- Do not include draft replies
    end)
    :map(M.build_root_draft_note)

  return draft_note_nodes
end

return M
