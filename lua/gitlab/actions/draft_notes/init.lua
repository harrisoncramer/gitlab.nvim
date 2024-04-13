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

---@class AddDraftNoteOpts table
---@field draft_note DraftNote
---@field unlinked boolean

---Adds a draft note to the draft notes state, then rebuilds the view
---@param opts AddDraftNoteOpts
M.add_draft_note = function(opts)
  local new_draft_notes = state.DRAFT_NOTES
  table.insert(new_draft_notes, opts.draft_note)
  state.DRAFT_NOTES = new_draft_notes
  local discussions = require("gitlab.actions.discussions")
  discussions.rebuild_discussion_tree()
end

--- @param bufnr integer
M.set_bufnr = function(bufnr)
  M.bufnr = bufnr
end

M.add_draft_notes_to_table = function()
  local draft_notes = List.new(state.DRAFT_NOTES)

  ---@param note DraftNote
  local draft_note_nodes = draft_notes:map(function(note)
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
  end)

  return draft_note_nodes

  -- TODO: Combine draft_notes and normal discussion nodes in the complex discussion
  -- tree. The code for that feature is a clusterfuck so this is difficult
  -- if state.settings.discussion_tree.tree_type == "simple" then
  --   return draft_note_nodes
  -- end
  --
  -- local discussion_module = require("gitlab.actions.discussions.tree")
  -- return discussion_module.create_node_list_by_file_name(draft_note_nodes)
end

---Send edits will actually send the edits to Gitlab and refresh the draft_notes tree
M.send_edits = function(note_id)
  return function(text)
    local body = { note = text }
    job.run_job(string.format("/mr/draft_notes/%d", note_id), "PATCH", body, function(data)
      u.notify(data.message, vim.log.levels.INFO)
      local new_draft_notes = List.new(state.DRAFT_NOTES):map(function(note)
        if note.id == note_id then
          note.note = text
        end
        return note
      end)
      state.DRAFT_NOTES = new_draft_notes
      local discussions = require("gitlab.actions.discussions")
      discussions.rebuild_discussion_tree()
    end)
  end
end

-- This function will actually send the deletion to Gitlab when you make a selection, and re-render the tree
M.send_deletion = function(tree)
  local current_node = tree:get_node()
  local note_node = common.get_note_node(tree, current_node)
  local root_node = common.get_root_node(tree, current_node)

  if note_node == nil or root_node == nil then
    u.notify("Could not get note or root node", vim.log.levels.ERROR)
    return
  end

  ---@type integer
  local note_id = note_node.is_root and root_node.id or note_node.id

  job.run_job(string.format("/mr/draft_notes/%d", note_id), "DELETE", nil, function(data)
    u.notify(data.message, vim.log.levels.INFO)
    local new_draft_notes = List.new(state.DRAFT_NOTES):filter(function(node)
      return node.id ~= note_id
    end)

    state.DRAFT_NOTES = new_draft_notes
    local discussions = require("gitlab.actions.discussions")
    discussions.rebuild_discussion_tree()
  end)
end

return M
