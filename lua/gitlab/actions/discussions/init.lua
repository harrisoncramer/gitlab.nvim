-- This module is responsible for the notes and comments discussion tree.
-- That includes things like editing existing notes in the tree,
-- replying to notes in the tree, and marking discussions as resolved/unresolved.
-- Draft notes are managed separately, under lua/gitlab/actions/draft_notes/init.lua

local Split = require("nui.split")
local Popup = require("nui.popup")
local NuiTree = require("nui.tree")
local job = require("gitlab.job")
local u = require("gitlab.utils")
local popup = require("gitlab.popup")
local state = require("gitlab.state")
local reviewer = require("gitlab.reviewer")
local common = require("gitlab.actions.common")
local List = require("gitlab.utils.list")
local tree_utils = require("gitlab.actions.discussions.tree")
local discussions_tree = require("gitlab.actions.discussions.tree")
local draft_notes = require("gitlab.actions.draft_notes")
local signs = require("gitlab.indicators.signs")
local diagnostics = require("gitlab.indicators.diagnostics")
local winbar = require("gitlab.actions.discussions.winbar")
local help = require("gitlab.actions.help")
local emoji = require("gitlab.emoji")
local windows = require("gitlab.actions.discussions.windows")

local M = {
  ---@type integer
  linked_bufnr = nil,
  ---@type integer
  unlinked_bufnr = nil,
  ---@type NuiTree?
  discussion_tree = nil,
  ---@type NuiTree?
  unlinked_discussion_tree = nil,
}

---Delete the buffer of one window's split, to prevent a leaked buffer on each open/close
---cycle.
---@param split_bufnr integer? Passed in because `unmount` has already nil'd `split.bufnr`.
local function delete_split_buf(split_bufnr)
  if split_bufnr ~= nil and vim.api.nvim_buf_is_valid(split_bufnr) then
    vim.api.nvim_buf_delete(split_bufnr, { force = true })
  end
end

---Delete the discussion buffers that all windows share, to prevent two leaked buffers on
---each open/close cycle.
local function delete_bufs()
  -- pairs, because either of these might be nil
  for _, bufnr in pairs({ M.linked_bufnr, M.unlinked_bufnr }) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end
end

---Find the registry entry owning `winid`, across all tabpages.
---@param winid integer
---@return DiscussionWindowEntry?
local function entry_for_winid(winid)
  local found
  windows.each(function(entry)
    if entry.winid == winid then
      found = entry
    end
  end)
  return found
end

---Re-fetch all discussions and re-render the relevant view.
---TODO: simplify the function signature - "unlinked" and "all" should not be two booleans
---@param unlinked boolean
---@param all? boolean
M.rebuild_view = function(unlinked, all)
  M.load_discussions(function()
    if all then
      M.rebuild_unlinked_discussion_tree()
      M.rebuild_discussion_tree()
    elseif unlinked then
      M.rebuild_unlinked_discussion_tree()
    else
      M.rebuild_discussion_tree()
    end
    state.discussion_tree.last_updated = os.time()
    M.refresh_diagnostics()
  end)
end

---Make API call to get the discussion data, stores it in the state, and calls the callback.
---@param callback? fun()
M.load_discussions = function(callback)
  local git = require("gitlab.git")
  require("gitlab.git_async").get_ahead_behind(
    git.get_current_branch(),
    git.get_remote_branch(),
    function(ahead, behind)
      state.ahead_behind = { ahead, behind }
    end
  )
  state.discussion_tree.last_updated = nil
  state.load_new_state("discussion_data", function(data)
    if not state.DISCUSSION_DATA then
      state.DISCUSSION_DATA = {}
    end
    state.DISCUSSION_DATA.discussions = u.ensure_table(data.discussions)
    state.DISCUSSION_DATA.unlinked_discussions = u.ensure_table(data.unlinked_discussions)
    state.DISCUSSION_DATA.emojis = u.ensure_table(data.emojis)
    if callback ~= nil then
      callback()
    end
  end)
end

---Initialize everything for discussions like setup of signs, callbacks for reviewer, etc.
M.initialize_discussions = function()
  state.discussion_tree.last_updated = os.time()
  signs.setup_signs()
  reviewer.set_callback_for_file_changed(function(args)
    diagnostics.place_diagnostics(args.buf)
    reviewer.update_winid_for_buffer(args.buf)
  end)
  reviewer.set_callback_for_reviewer_enter(function()
    M.refresh_diagnostics()
  end)
  reviewer.set_callback_for_buf_read(function(args)
    vim.api.nvim_set_option_value("modifiable", false, { buf = args.buf })
    reviewer.update_winid_for_buffer(args.buf)
    reviewer.set_keymaps(args.buf)
    reviewer.set_reviewer_autocommands(args.buf)
  end)
  reviewer.set_callback_for_reviewer_leave(function()
    signs.clear_signs()
    diagnostics.clear_diagnostics()
  end)
end

---Take existing data and refresh the diagnostics and the signs.
M.refresh_diagnostics = function()
  if state.settings.discussion_signs.enabled then
    diagnostics.refresh_diagnostics()
    require("gitlab.reviewer.history").refresh_diagnostics()
  end
  common.add_empty_titles()
end

---Open the discussion and unlinked note trees and set the keybindings.
---@param callback? function
---@param view_type? "discussions"|"notes" Defines the view type to select (useful for overriding the default view type when jumping to discussion tree when it's closed)
M.open = function(callback, view_type)
  local original_window = vim.api.nvim_get_current_win() -- The window from which ther user called M.open
  local tabid = vim.api.nvim_get_current_tabpage()

  local requested_view_type = view_type and view_type or state.settings.discussion_tree.default_view
  state.DISCUSSION_DATA = u.ensure_table(state.DISCUSSION_DATA)
  state.DISCUSSION_DATA.discussions = u.ensure_table(state.DISCUSSION_DATA.discussions)
  state.DISCUSSION_DATA.unlinked_discussions = u.ensure_table(state.DISCUSSION_DATA.unlinked_discussions)
  state.DRAFT_NOTES = u.ensure_table(state.DRAFT_NOTES)

  -- The current tabpage already has a discussion window; focus it instead of mounting a
  -- second one.
  local existing = windows.get(tabid)
  if existing then
    vim.api.nvim_set_current_win(existing.winid)
    if type(callback) == "function" then
      callback()
    end
    return
  end

  local is_first_window = not windows.any()

  -- Make discussion split window, creating the shared buffers only for the first window
  -- (later tabs reuse them, so they show the same tree).
  local split = M.create_split()
  if is_first_window then
    M.linked_bufnr, M.unlinked_bufnr = M.create_bufs()
  end
  split:mount()

  windows.set(tabid, { split = split, winid = split.winid, bufnr = M.linked_bufnr, view_type = requested_view_type })

  -- Set window and buffer local options to discussion tree split after mounting the split
  for opt, val in pairs(state.settings.discussion_tree.winopts) do
    vim.api.nvim_set_option_value(opt, val, { win = split.winid })
  end

  if is_first_window then
    vim.api.nvim_set_option_value("filetype", "gitlab", { buf = M.linked_bufnr })
    vim.api.nvim_set_option_value("filetype", "gitlab", { buf = M.unlinked_bufnr })

    -- Set autocmds to clean up state when discussions buffers are deleted manually
    vim.api.nvim_create_autocmd("BufWipeout", {
      buffer = M.linked_bufnr,
      callback = function()
        M.linked_bufnr = nil
      end,
    })
    vim.api.nvim_create_autocmd("BufWipeout", {
      buffer = M.unlinked_bufnr,
      callback = function()
        M.unlinked_bufnr = nil
      end,
    })
  end

  -- Set autocmd to clean up state when this tab's discussion split is closed manually
  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(split.winid),
    callback = function()
      windows.remove_by_winid(split.winid)
      if not windows.any() then
        winbar.cleanup_timer()
      end
      -- nui nils `split.bufnr` as it tears the split down, so read it while it is still set.
      local split_bufnr = split.bufnr
      -- Unmount, or the split keeps its buffer and augroups for the rest of the session,
      -- one set per window the user closes by hand. Defer it: delete_bufs wipes the
      -- discussion buffers, and a buffer wiped from inside this callback fires no
      -- BufWipeout, so the autocmds above would never reset the bufnr fields.
      vim.schedule(function()
        pcall(function()
          split:unmount()
        end)
        delete_split_buf(split_bufnr)
        if not windows.any() then
          delete_bufs()
        end
      end)
    end,
  })

  -- Initialize winbar
  if is_first_window then
    winbar.start_timer()
  end

  -- Rebuild trees in order to set keymaps and make buffers protected
  M.switch_view_type(requested_view_type)
  M.rebuild_unlinked_discussion_tree()
  M.rebuild_discussion_tree()

  -- Focus the correct window
  local win_to_enter = not state.settings.discussion_tree.focus_on_open and original_window or split.winid
  if vim.api.nvim_win_is_valid(win_to_enter) then
    vim.api.nvim_set_current_win(win_to_enter)
  end

  -- Relooad data
  draft_notes.rebuild_view(false, true)

  if type(callback) == "function" then
    callback()
  end
end

---Unmount the discussion split of `tabid` (default: the current tabpage).
---@param tabid integer?
M.close = function(tabid)
  tabid = tabid or vim.api.nvim_get_current_tabpage()
  local entry = windows.get(tabid)
  if entry == nil then
    return
  end
  -- nui nils `split.bufnr` as it tears the split down, so read it while it is still set.
  local split_bufnr = entry.split.bufnr
  if vim.api.nvim_win_is_valid(entry.winid) then
    local ok, err = pcall(vim.api.nvim_win_close, entry.winid, true)
    if not ok and tostring(err):find("E444") then
      -- Last window in the session, so it needs a sibling before it can be closed.
      vim.cmd("silent! vsplit")
      ok = pcall(vim.api.nvim_win_close, entry.winid, true)
    end
    if not ok then
      u.notify("Could not close the discussion window", vim.log.levels.WARN)
      return
    end
  end
  -- Release nui's own buffer and augroups, which nothing else frees. Guarded so a failure
  -- in there cannot skip the state cleanup below.
  pcall(function()
    entry.split:unmount()
  end)
  delete_split_buf(split_bufnr)
  windows.remove(tabid)
  if not windows.any() then
    winbar.cleanup_timer()
    delete_bufs()
  end
end

---Unmount every registered discussion window, across all tabpages. A window left in
---another tab would otherwise keep showing the outgoing MR's discussions and hold its
---NuiSplit buffer and augroups.
M.close_all = function()
  local tabids = {}
  windows.each(function(_, tabid)
    table.insert(tabids, tabid)
  end)
  -- Close after collecting: it fires WinClosed, which mutates the registry we'd otherwise
  -- still be iterating.
  for _, tabid in ipairs(tabids) do
    M.close(tabid)
  end
  winbar.cleanup_timer()
end

---Move to the discussion tree at the discussion from diagnostic on current line.
M.move_to_discussion_tree = function()
  local tabid = vim.api.nvim_get_current_tabpage()
  local current_line = vim.api.nvim_win_get_cursor(0)[1]
  local d = vim.diagnostic.get(0, { namespace = diagnostics.diagnostics_namespace, lnum = current_line - 1 })

  ---Function used to jump to the discussion tree after the menu selection.
  local jump_after_menu_selection = function(diagnostic)
    ---Function used to jump to the discussion tree after the discussion tree is opened.
    local jump_after_tree_opened = function()
      -- All diagnostics in `diagnotics_namespace` have diagnostic_id
      local discussion_id = diagnostic.user_data.discussion_id
      local discussion_node, line_number = M.discussion_tree:get_node("-" .. discussion_id)
      if discussion_node == nil or next(discussion_node) == nil then
        u.notify("Discussion not found", vim.log.levels.WARN)
        return
      end
      if not discussion_node:is_expanded() then
        for _, child in ipairs(discussion_node:get_child_ids()) do
          M.discussion_tree:get_node(child):expand()
        end
        discussion_node:expand()
      end
      M.discussion_tree:render()
      local entry = windows.get(tabid)
      if entry then
        vim.api.nvim_set_current_win(entry.winid)
        M.switch_view_type("discussions")
        vim.api.nvim_win_set_cursor(entry.winid, { line_number, 0 })
      else
        u.notify("Discussion tree window not found", vim.log.levels.WARN)
      end
    end

    if windows.get(tabid) == nil then
      M.open(jump_after_tree_opened, "discussions")
    else
      jump_after_tree_opened()
    end
  end

  if #d == 0 then
    local entry = windows.get(tabid)
    if state.settings.reviewer_settings.jump_with_no_diagnostics and entry then
      vim.api.nvim_win_set_cursor(entry.winid, { entry.last_row, entry.last_column })
      vim.api.nvim_set_current_win(entry.winid)
    else
      u.notify("No diagnostics for this line.", vim.log.levels.WARN)
    end
    return
  elseif #d > 1 then
    vim.ui.select(d, {
      prompt = "Choose discussion to jump to",
      format_item = function(diagnostic)
        return diagnostic.message
      end,
    }, function(diagnostic)
      if not diagnostic then
        return
      end
      jump_after_menu_selection(diagnostic)
    end)
  else
    jump_after_menu_selection(d[1])
  end
end

---Open a reply popup for a note in the discussion tree.
---@param tree NuiTree
M.reply = function(tree)
  if M.is_draft_note(tree) then
    u.notify("Gitlab does not support replying to draft notes", vim.log.levels.WARN)
    return
  end

  local node = common.get_current_node(tree)
  local discussion_node = common.get_root_node(tree, node)

  if discussion_node == nil then
    u.notify("Could not get discussion root", vim.log.levels.ERROR)
    return
  end

  local discussion_id = tostring(discussion_node.id)
  local comment = require("gitlab.actions.comment")
  local unlinked = tree.bufnr == M.unlinked_bufnr
  local layout = comment.create_comment_layout({
    discussion_id = discussion_id,
    unlinked = unlinked,
    reply = true,
    file_name = discussion_node.file_name,
  })

  layout:mount()
end

---Open a popup prompting the user to delete the current comment.
---@param tree NuiTree
---@param unlinked boolean
M.delete_comment = function(tree, unlinked)
  vim.ui.select({ "Confirm", "Cancel" }, {
    prompt = "Delete comment?",
  }, function(choice)
    if choice == "Confirm" then
      local current_node = common.get_current_node(tree)
      local note_node = common.get_note_node(tree, current_node)
      local root_node = common.get_root_node(tree, current_node)
      if note_node == nil or root_node == nil then
        u.notify("Could not get note or root node", vim.log.levels.ERROR)
        return
      end

      ---@type integer
      if M.is_draft_note(tree) then
        draft_notes.confirm_delete_draft_note(note_node.id, unlinked)
      else
        local note_id = note_node.is_root and root_node.root_note_id or note_node.id
        local comment = require("gitlab.actions.comment")
        comment.confirm_delete_comment(note_id, root_node.id, unlinked)
      end
    end
  end)
end

---Open the edit popup for the current comment in the discussion tree.
---@param tree NuiTree
---@param unlinked boolean
M.edit_comment = function(tree, unlinked)
  local current_node = common.get_current_node(tree)
  local note_node = common.get_note_node(tree, current_node)
  local root_node = common.get_root_node(tree, current_node)
  if note_node == nil or root_node == nil then
    u.notify("Could not get root or note node", vim.log.levels.ERROR)
    return
  end
  local title = "Edit Comment"
  title = root_node.file_name ~= nil and string.format("%s [%s]", title, root_node.file_name) or title
  local edit_popup = Popup(popup.create_popup_state({ title = title, user_settings = state.settings.popup.edit }))

  popup.set_up_autocommands(edit_popup, nil, vim.api.nvim_get_current_win())

  edit_popup:mount()

  -- Gather all lines from immediate children that aren't note nodes
  local lines = List.new(note_node:get_child_ids()):reduce(function(agg, child_id)
    local child_node = tree:get_node(child_id)
    if child_node and not child_node:has_children() then
      local line = tree:get_node(child_id).text
      table.insert(agg, line)
    end
    return agg
  end, {})

  local currentBuffer = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(currentBuffer, 0, -1, false, lines)

  -- Draft notes module handles edits for draft notes
  if M.is_draft_note(tree) then
    popup.set_popup_keymaps(
      edit_popup,
      draft_notes.confirm_edit_draft_note(note_node.id, unlinked),
      nil,
      popup.editable_popup_opts
    )
  else
    local comment = require("gitlab.actions.comment")
    popup.set_popup_keymaps(
      edit_popup,
      comment.confirm_edit_comment(tostring(root_node.id), note_node.root_note_id or note_node.id, unlinked),
      nil,
      popup.editable_popup_opts
    )
  end
end

---Toggle the resolved status of the current discussion and send the change to the Go server.
---@param tree NuiTree
M.toggle_discussion_resolved = function(tree)
  local note = common.get_current_node(tree)
  if note == nil then
    return
  end

  -- Switch to the root node to enable toggling from child nodes and note bodies
  if not note.resolvable and common.is_node_note(note) then
    note = common.get_root_node(tree, note)
  end
  if note == nil then
    return
  end

  local body = {
    discussion_id = note.id,
    resolved = not note.resolved,
  }

  job.run_job("/mr/discussions/resolve", "PUT", body, function(data)
    u.notify(data.message, vim.log.levels.INFO)
    local unlinked = tree.bufnr == M.unlinked_bufnr
    M.rebuild_view(unlinked)
  end)
end

---Open a popup prompting the user to choose an emoji to attach to the current node.
---@param tree any
---@param unlinked boolean
M.add_emoji_to_note = function(tree, unlinked)
  local node = common.get_current_node(tree)
  local note_node = common.get_note_node(tree, node)

  if note_node == nil then
    u.notify("Could not get note", vim.log.levels.ERROR)
    return
  end

  local note_id = note_node.root_note_id or note_node.id
  local emojis = require("gitlab.emoji").emoji_list
  emoji.pick_emoji(emojis, function(name)
    local body = { emoji = name, note_id = note_id }
    job.run_job("/mr/awardable/note/", "POST", body, function()
      u.notify("Emoji added", vim.log.levels.INFO)
      M.rebuild_view(unlinked)
    end)
  end)
end

---Open a popup prompting the user to choose an emoji to remove from the current node.
---@param tree any
---@param unlinked boolean
M.delete_emoji_from_note = function(tree, unlinked)
  local node = common.get_current_node(tree)
  local note_node = common.get_note_node(tree, node)

  if note_node == nil then
    u.notify("Could not get note", vim.log.levels.ERROR)
    return
  end

  local note_id = note_node.root_note_id or note_node.id
  local note_id_str = tostring(note_id)

  local e = require("gitlab.emoji")

  local emojis = {}
  local current_emojis = state.DISCUSSION_DATA.emojis[note_id_str]
  for _, current_emoji in ipairs(current_emojis) do
    if state.USER.id == current_emoji.user.id then
      table.insert(emojis, e.emoji_map[current_emoji.name])
    end
  end

  emoji.pick_emoji(emojis, function(name)
    local awardable_id
    for _, current_emoji in ipairs(current_emojis) do
      if current_emoji.name == name and current_emoji.user.id == state.USER.id then
        awardable_id = current_emoji.id
        break
      end
    end
    job.run_job(string.format("/mr/awardable/note/%d/%d", note_id, awardable_id), "DELETE", nil, function()
      u.notify("Emoji removed", vim.log.levels.INFO)
      M.rebuild_view(unlinked)
    end)
  end)
end

--
-- 🌲 Helper Functions
--

---Collect all nodes in a tree prior to rebuilding it, so they can be re-expanded before render.
---@param tree? NuiTree
---@return table
M.gather_expanded_node_ids = function(tree)
  -- Gather all nodes for later expansion, after rebuild
  local ids = {}
  for id, node in pairs(tree and tree.nodes.by_id or {}) do
    if node._is_expanded then
      table.insert(ids, id)
    end
  end
  return ids
end

---Rebuild the discussion tree, which contains all comments and draft comments linked to
---specific places in the code.
M.rebuild_discussion_tree = function()
  if M.linked_bufnr == nil then
    return
  end

  -- The buffer is shared between windows, and the rebuild clears and re-adds its lines.
  -- Capture the cursor per window, or only one window's position survives.
  local restore_targets = {}
  windows.each(function(entry)
    if entry.bufnr == M.linked_bufnr then
      table.insert(restore_targets, {
        winid = entry.winid,
        node = discussions_tree.get_node_at_cursor(M.discussion_tree, entry.winid, entry.last_node_at_cursor),
        column = vim.api.nvim_win_get_cursor(entry.winid)[2],
      })
    end
  end)

  local expanded_node_ids = M.gather_expanded_node_ids(M.discussion_tree)
  common.switch_can_edit_bufs(true, M.linked_bufnr, M.unlinked_bufnr)

  vim.api.nvim_buf_set_lines(M.linked_bufnr, 0, -1, false, {})
  local existing_comment_nodes = discussions_tree.add_discussions_to_table(state.DISCUSSION_DATA.discussions, false)
  local draft_comment_nodes = draft_notes.add_draft_notes_to_table(false)

  -- Combine inline draft notes with regular comments
  local all_nodes = u.join(draft_comment_nodes, existing_comment_nodes)

  local discussion_tree = NuiTree({
    nodes = all_nodes,
    bufnr = M.linked_bufnr,
    prepare_node = tree_utils.nui_tree_prepare_node,
  })

  -- Re-expand already expanded nodes
  for _, id in ipairs(expanded_node_ids) do
    tree_utils.open_node_by_id(discussion_tree, id)
  end
  discussion_tree:render()
  for _, target in ipairs(restore_targets) do
    discussions_tree.restore_cursor_position(target.winid, discussion_tree, target.column, target.node, nil)
  end

  M.set_tree_keymaps(discussion_tree, M.linked_bufnr, false)
  M.discussion_tree = discussion_tree
  common.switch_can_edit_bufs(false, M.linked_bufnr, M.unlinked_bufnr)
  state.discussion_tree.resolved_expanded = false
  state.discussion_tree.unresolved_expanded = false
end

---Rebuild the unlinked discussion tree, which contains all notes and draft notes.
M.rebuild_unlinked_discussion_tree = function()
  if M.unlinked_bufnr == nil then
    return
  end

  -- Capture cursor state per registered window, see M.rebuild_discussion_tree.
  local restore_targets = {}
  windows.each(function(entry)
    if entry.bufnr == M.unlinked_bufnr then
      table.insert(restore_targets, {
        winid = entry.winid,
        node = discussions_tree.get_node_at_cursor(M.unlinked_discussion_tree, entry.winid, entry.last_node_at_cursor),
        column = vim.api.nvim_win_get_cursor(entry.winid)[2],
      })
    end
  end)

  local expanded_node_ids = M.gather_expanded_node_ids(M.unlinked_discussion_tree)
  common.switch_can_edit_bufs(true, M.linked_bufnr, M.unlinked_bufnr)
  vim.api.nvim_buf_set_lines(M.unlinked_bufnr, 0, -1, false, {})
  local existing_note_nodes =
    discussions_tree.add_discussions_to_table(state.DISCUSSION_DATA.unlinked_discussions, true)
  local draft_comment_nodes = draft_notes.add_draft_notes_to_table(true)

  -- Combine draft notes with regular notes
  local all_nodes = u.join(draft_comment_nodes, existing_note_nodes)

  local unlinked_discussion_tree = NuiTree({
    nodes = all_nodes,
    bufnr = M.unlinked_bufnr,
    prepare_node = tree_utils.nui_tree_prepare_node,
  })

  -- Re-expand already expanded nodes
  for _, id in ipairs(expanded_node_ids) do
    tree_utils.open_node_by_id(unlinked_discussion_tree, id)
  end
  unlinked_discussion_tree:render()
  for _, target in ipairs(restore_targets) do
    discussions_tree.restore_cursor_position(target.winid, unlinked_discussion_tree, target.column, target.node)
  end

  M.set_tree_keymaps(unlinked_discussion_tree, M.unlinked_bufnr, true)
  M.unlinked_discussion_tree = unlinked_discussion_tree
  common.switch_can_edit_bufs(false, M.linked_bufnr, M.unlinked_bufnr)
  state.unlinked_discussion_tree.resolved_expanded = false
  state.unlinked_discussion_tree.unresolved_expanded = false
end

---Create the split window for the discussion tree in the current tabpage.
---@return NuiSplit
M.create_split = function()
  local position = state.settings.discussion_tree.position
  local size = state.settings.discussion_tree.size
  local relative = state.settings.discussion_tree.relative

  return Split({
    relative = relative,
    position = position,
    size = size,
  })
end

---Create the linked/unlinked discussion buffers, shared by every discussion window, and
---their cursor-tracking autocmds.
---@return integer linked_bufnr
---@return integer unlinked_bufnr
M.create_bufs = function()
  local linked_bufnr = vim.api.nvim_create_buf(true, false)
  local unlinked_bufnr = vim.api.nvim_create_buf(true, false)

  vim.api.nvim_create_autocmd("WinLeave", {
    buffer = linked_bufnr,
    callback = function()
      local entry = entry_for_winid(vim.api.nvim_get_current_win())
      if entry == nil then
        return
      end
      entry.last_row, entry.last_column = unpack(vim.api.nvim_win_get_cursor(0))
      entry.last_node_at_cursor = M.discussion_tree and M.discussion_tree:get_node(entry.last_row) or nil
    end,
  })

  vim.api.nvim_create_autocmd("WinLeave", {
    buffer = unlinked_bufnr,
    callback = function()
      local entry = entry_for_winid(vim.api.nvim_get_current_win())
      if entry == nil then
        return
      end
      local cursor_row = vim.api.nvim_win_get_cursor(0)[1]
      entry.last_node_at_cursor = M.unlinked_discussion_tree and M.unlinked_discussion_tree:get_node(cursor_row) or nil
    end,
  })

  return linked_bufnr, unlinked_bufnr
end

---Check if type of current node is note or note body.
---@param tree NuiTree
---@return boolean
M.is_current_node_note = function(tree)
  return common.is_node_note(common.get_current_node(tree))
end

---Set the discussion tree keymaps.
---@param tree NuiTree The current discussion tree
---@param bufnr integer The number of the buffer that holds the discussion tree
---@param unlinked boolean If true, the comment is not linked to a line
M.set_tree_keymaps = function(tree, bufnr, unlinked)
  -- Require keymaps only after user settings have been merged with defaults
  local keymaps = require("gitlab.state").settings.keymaps
  if keymaps.disable_all or keymaps.discussion_tree.disable_all then
    return
  end

  ---Keybindings only relevant for linked (comment) view
  if not unlinked then
    if keymaps.discussion_tree.jump_to_file then
      vim.keymap.set("n", keymaps.discussion_tree.jump_to_file, function()
        if M.is_current_node_note(tree) then
          common.jump_to_file(tree)
        end
      end, { buffer = bufnr, desc = "Jump to file", nowait = keymaps.discussion_tree.jump_to_file_nowait })
    end

    if keymaps.discussion_tree.jump_to_reviewer then
      vim.keymap.set("n", keymaps.discussion_tree.jump_to_reviewer, function()
        if M.is_current_node_note(tree) then
          common.jump_to_reviewer(tree)
        end
      end, { buffer = bufnr, desc = "Jump to reviewer", nowait = keymaps.discussion_tree.jump_to_reviewer_nowait })
    end

    if keymaps.discussion_tree.toggle_tree_type then
      vim.keymap.set("n", keymaps.discussion_tree.toggle_tree_type, function()
        M.toggle_tree_type()
      end, {
        buffer = bufnr,
        desc = "Change tree type between `simple` and `by_file_name`",
        nowait = keymaps.discussion_tree.toggle_tree_type_nowait,
      })
    end
  end

  if keymaps.discussion_tree.refresh_data then
    vim.keymap.set("n", keymaps.discussion_tree.refresh_data, function()
      draft_notes.rebuild_view(unlinked, false)
    end, {
      buffer = bufnr,
      desc = "Refresh the view with Gitlab's APIs",
      nowait = keymaps.discussion_tree.refresh_data_nowait,
    })
  end

  if keymaps.discussion_tree.edit_comment then
    vim.keymap.set("n", keymaps.discussion_tree.edit_comment, function()
      if M.is_current_node_note(tree) then
        M.edit_comment(tree, unlinked)
      end
    end, { buffer = bufnr, desc = "Edit comment", nowait = keymaps.discussion_tree.edit_comment_nowait })
  end

  if keymaps.discussion_tree.publish_draft then
    vim.keymap.set("n", keymaps.discussion_tree.publish_draft, function()
      if M.is_draft_note(tree) then
        draft_notes.publish_draft(tree)
      end
    end, { buffer = bufnr, desc = "Publish draft", nowait = keymaps.discussion_tree.publish_draft_nowait })
  end

  if keymaps.discussion_tree.delete_comment then
    vim.keymap.set("n", keymaps.discussion_tree.delete_comment, function()
      if M.is_current_node_note(tree) then
        M.delete_comment(tree, unlinked)
      end
    end, { buffer = bufnr, desc = "Delete comment", nowait = keymaps.discussion_tree.delete_comment_nowait })
  end

  if keymaps.discussion_tree.toggle_draft_mode then
    vim.keymap.set("n", keymaps.discussion_tree.toggle_draft_mode, function()
      M.toggle_draft_mode()
    end, {
      buffer = bufnr,
      desc = "Toggle between draft mode and live mode",
      nowait = keymaps.discussion_tree.toggle_draft_mode_nowait,
    })
  end

  if keymaps.discussion_tree.toggle_sort_method then
    vim.keymap.set("n", keymaps.discussion_tree.toggle_sort_method, function()
      M.toggle_sort_method()
    end, {
      buffer = bufnr,
      desc = "Toggle sort method",
      nowait = keymaps.discussion_tree.toggle_sort_method_nowait,
    })
  end

  if keymaps.discussion_tree.toggle_date_format then
    vim.keymap.set("n", keymaps.discussion_tree.toggle_date_format, function()
      M.toggle_date_format()
    end, {
      buffer = bufnr,
      desc = "Toggle date format",
      nowait = keymaps.discussion_tree.toggle_date_format_nowait,
    })
  end

  if keymaps.discussion_tree.toggle_resolved then
    vim.keymap.set("n", keymaps.discussion_tree.toggle_resolved, function()
      if M.is_current_node_note(tree) and not M.is_draft_note(tree) then
        M.toggle_discussion_resolved(tree)
      end
    end, { buffer = bufnr, desc = "Toggle resolved", nowait = keymaps.discussion_tree.toggle_resolved_nowait })
  end

  if keymaps.discussion_tree.toggle_node then
    vim.keymap.set("n", keymaps.discussion_tree.toggle_node, function()
      local entry = windows.get()
      if entry == nil then
        return
      end
      tree_utils.toggle_node(entry.winid, tree)
    end, { buffer = bufnr, desc = "Toggle node", nowait = keymaps.discussion_tree.toggle_node_nowait })
  end

  if keymaps.discussion_tree.toggle_all_discussions then
    vim.keymap.set("n", keymaps.discussion_tree.toggle_all_discussions, function()
      local entry = windows.get()
      if entry == nil then
        return
      end
      tree_utils.toggle_nodes(entry.winid, tree, unlinked, {
        toggle_resolved = true,
        toggle_unresolved = true,
        keep_current_open = state.settings.discussion_tree.keep_current_open,
      })
    end, {
      buffer = bufnr,
      desc = "Toggle all nodes",
      nowait = keymaps.discussion_tree.toggle_all_discussions_nowait,
    })
  end

  if keymaps.discussion_tree.toggle_resolved_discussions then
    vim.keymap.set("n", keymaps.discussion_tree.toggle_resolved_discussions, function()
      local entry = windows.get()
      if entry == nil then
        return
      end
      tree_utils.toggle_nodes(entry.winid, tree, unlinked, {
        toggle_resolved = true,
        toggle_unresolved = false,
        keep_current_open = state.settings.discussion_tree.keep_current_open,
      })
    end, {
      buffer = bufnr,
      desc = "Toggle resolved nodes",
      nowait = keymaps.discussion_tree.toggle_resolved_discussions_nowait,
    })
  end

  if keymaps.discussion_tree.toggle_unresolved_discussions then
    vim.keymap.set("n", keymaps.discussion_tree.toggle_unresolved_discussions, function()
      local entry = windows.get()
      if entry == nil then
        return
      end
      tree_utils.toggle_nodes(entry.winid, tree, unlinked, {
        toggle_resolved = false,
        toggle_unresolved = true,
        keep_current_open = state.settings.discussion_tree.keep_current_open,
      })
    end, {
      buffer = bufnr,
      desc = "Toggle unresolved nodes",
      nowait = keymaps.discussion_tree.toggle_unresolved_discussions_nowait,
    })
  end

  if keymaps.discussion_tree.reply then
    vim.keymap.set("n", keymaps.discussion_tree.reply, function()
      if M.is_current_node_note(tree) then
        M.reply(tree)
      end
    end, { buffer = bufnr, desc = "Reply", nowait = keymaps.discussion_tree.reply_nowait })
  end

  if keymaps.discussion_tree.switch_view then
    vim.keymap.set("n", keymaps.discussion_tree.switch_view, function()
      M.switch_view_type()
    end, {
      buffer = bufnr,
      desc = "Change view type between discussions and notes",
      nowait = keymaps.discussion_tree.switch_view_nowait,
    })
  end

  if keymaps.help then
    vim.keymap.set("n", keymaps.help, function()
      help.open({ discussion_tree = true })
    end, { buffer = bufnr, desc = "Open help popup", nowait = keymaps.help_nowait })
  end

  if keymaps.discussion_tree.open_in_browser then
    vim.keymap.set("n", keymaps.discussion_tree.open_in_browser, function()
      common.open_in_browser(tree)
    end, {
      buffer = bufnr,
      desc = "Open the note in your browser",
      nowait = keymaps.discussion_tree.open_in_browser_nowait,
    })
  end

  if keymaps.discussion_tree.copy_node_url then
    vim.keymap.set("n", keymaps.discussion_tree.copy_node_url, function()
      common.copy_node_url(tree)
    end, {
      buffer = bufnr,
      desc = "Copy the URL of the current node to clipboard",
      nowait = keymaps.discussion_tree.copy_node_url_nowait,
    })
  end

  if keymaps.discussion_tree.print_node then
    vim.keymap.set("n", keymaps.discussion_tree.print_node, function()
      common.print_node(tree)
    end, {
      buffer = bufnr,
      desc = "Print current node (for debugging)",
      nowait = keymaps.discussion_tree.print_node_nowait,
    })
  end

  if keymaps.discussion_tree.add_emoji then
    vim.keymap.set("n", keymaps.discussion_tree.add_emoji, function()
      M.add_emoji_to_note(tree, unlinked)
    end, {
      buffer = bufnr,
      desc = "Add an emoji reaction to the note/comment",
      nowait = keymaps.discussion_tree.add_emoji_nowait,
    })
  end

  if keymaps.discussion_tree.delete_emoji then
    vim.keymap.set("n", keymaps.discussion_tree.delete_emoji, function()
      M.delete_emoji_from_note(tree, unlinked)
    end, {
      buffer = bufnr,
      desc = "Remove an emoji reaction from the note/comment",
      nowait = keymaps.discussion_tree.delete_emoji_nowait,
    })
  end

  emoji.init_popup(tree, bufnr)
end

---Toggle the view type of the current tabpage's discussion window, or set it to
---`override`.
---@param override? "discussions"|"notes" The view type to select
M.switch_view_type = function(override)
  local entry = windows.get()
  if entry == nil then
    return
  end
  vim.api.nvim_set_option_value("winfixbuf", false, { win = entry.winid })
  if override == "discussions" or entry.view_type == "notes" then
    entry.view_type = "discussions"
    entry.bufnr = M.linked_bufnr
    vim.api.nvim_win_set_buf(entry.winid, entry.bufnr)
  elseif override == "notes" or entry.view_type == "discussions" then
    entry.view_type = "notes"
    entry.bufnr = M.unlinked_bufnr
    vim.api.nvim_win_set_buf(entry.winid, entry.bufnr)
  end
  vim.api.nvim_set_option_value("winfixbuf", true, { win = entry.winid })
  winbar.update_winbar()
end

---Toggle comments tree type between "simple" and "by_file_name".
M.toggle_tree_type = function()
  if state.settings.discussion_tree.tree_type == "simple" then
    state.settings.discussion_tree.tree_type = "by_file_name"
  else
    state.settings.discussion_tree.tree_type = "simple"
  end
  M.rebuild_discussion_tree()
end

---Toggle between creating comments as drafts and publishing immediately.
M.toggle_draft_mode = function()
  state.settings.discussion_tree.draft_mode = not state.settings.discussion_tree.draft_mode
end

---Toggle between sorting by "original comment" (oldest first) or "latest reply" (newest first).
M.toggle_sort_method = function()
  if state.settings.discussion_tree.sort_by == "original_comment" then
    state.settings.discussion_tree.sort_by = "latest_reply"
  else
    state.settings.discussion_tree.sort_by = "original_comment"
  end
  winbar.update_winbar()
  M.rebuild_view(false, true)
end

---Toggle between displaying relative time ("5 days ago") and absolute ("04/10/2025 at 22:49").
M.toggle_date_format = function()
  state.settings.discussion_tree.relative_date = not state.settings.discussion_tree.relative_date
  M.rebuild_unlinked_discussion_tree()
  M.rebuild_discussion_tree()
end

---Indicate whether the node under the cursor is a draft note or not.
---@param tree NuiTree
---@return boolean
M.is_draft_note = function(tree)
  local current_node = common.get_current_node(tree)
  local note_node = common.get_note_node(tree, current_node)
  if note_node and note_node.is_draft then
    return true
  end
  local root_node = common.get_root_node(tree, current_node)
  return root_node ~= nil and root_node.is_draft
end

return M
