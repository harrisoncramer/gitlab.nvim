-- This module is responsible for the discussion tree. That includes things like
-- editing existing notes in the tree, replying to notes in the tree,
-- and marking discussions as resolved/unresolved.
local Split = require("nui.split")
local Popup = require("nui.popup")
local NuiTree = require("nui.tree")
local NuiLine = require("nui.line")
local Layout = require("nui.layout")
local job = require("gitlab.job")
local u = require("gitlab.utils")
local state = require("gitlab.state")
local reviewer = require("gitlab.reviewer")
local miscellaneous = require("gitlab.actions.miscellaneous")
local discussions_tree = require("gitlab.actions.discussions.tree")

local edit_popup = Popup(u.create_popup_state("Edit Comment", "80%", "80%"))
local reply_popup = Popup(u.create_popup_state("Reply", "80%", "80%"))
local discussion_sign_name = "gitlab_discussion"
local discussion_helper_sign_start = "gitlab_discussion_helper_start"
local discussion_helper_sign_mid = "gitlab_discussion_helper_mid"
local discussion_helper_sign_end = "gitlab_discussion_helper_end"
local diagnostics_namespace = vim.api.nvim_create_namespace(discussion_sign_name)

local M = {
  layout_visible = false,
  layout = nil,
  layout_buf = nil,
  ---@type Discussion[]
  discussions = {},
  ---@type UnlinkedDiscussion[]
  unlinked_discussions = {},
  linked_section = nil,
  unlinked_section = nil,
  discussion_tree = nil,
}

---Load the discussion data, storage them in M.discussions and M.unlinked_discussions and call
---callback with data
---@param callback fun(data: DiscussionData): nil
M.load_discussions = function(callback)
  job.run_job("/discussions/list", "POST", { blacklist = state.settings.discussion_tree.blacklist }, function(data)
    M.discussions = data.discussions
    M.unlinked_discussions = data.unlinked_discussions
    callback(data)
  end)
end

---Parse line code and return old and new line numbers
---@param line_code string gitlab line code -> 588440f66559714280628a4f9799f0c4eb880a4a_10_10
---@return number?
---@return number?
local function _parse_line_code(line_code)
  local line_code_regex = "%w+_(%d+)_(%d+)"
  local old_line, new_line = line_code:match(line_code_regex)
  return tonumber(old_line), tonumber(new_line)
end

---Filter all discussions which are relevant for currently visible signs and diagnostscs.
---@return Discussion[]?
M.filter_discussions_for_signs_and_diagnostics = function()
  if type(M.discussions) ~= "table" then
    return
  end
  local file = reviewer.get_current_file()
  if not file then
    return
  end
  local discussions = {}
  for _, discussion in ipairs(M.discussions) do
    local first_note = discussion.notes[1]
    if
      type(first_note.position) == "table"
      and (first_note.position.new_path == file or first_note.position.old_path == file)
    then
      if
        --Skip resolved discussions
        not (
          state.settings.discussion_sign_and_diagnostic.skip_resolved_discussion
          and first_note.resolvable
          and first_note.resolved
        )
        --Skip discussions from old revisions
        and not (
          state.settings.discussion_sign_and_diagnostic.skip_old_revision_discussion
          and u.from_iso_format_date_to_timestamp(first_note.created_at)
            <= u.from_iso_format_date_to_timestamp(state.MR_REVISIONS[1].created_at)
        )
      then
        table.insert(discussions, discussion)
      end
    end
  end
  return discussions
end

---Refresh the discussion signs for currently loaded file in reviewer For convinience we use same
---string for sign name and sign group ( currently there is only one sign needed)
M.refresh_signs = function()
  local diagnostics = M.filter_discussions_for_signs_and_diagnostics()
  if diagnostics == nil then
    vim.diagnostic.reset(diagnostics_namespace)
    return
  end

  local new_signs = {}
  local old_signs = {}
  for _, discussion in ipairs(diagnostics) do
    local first_note = discussion.notes[1]
    local base_sign = {
      name = discussion_sign_name,
      group = discussion_sign_name,
      priority = state.settings.discussion_sign.priority,
    }
    local base_helper_sign = {
      name = discussion_sign_name,
      group = discussion_sign_name,
      priority = state.settings.discussion_sign.priority - 1,
    }
    if first_note.position.line_range ~= nil then
      local start_old_line, start_new_line = _parse_line_code(first_note.position.line_range.start.line_code)
      local end_old_line, end_new_line = _parse_line_code(first_note.position.line_range["end"].line_code)
      local discussion_line, start_line, end_line
      if first_note.position.line_range.start.type == "new" then
        table.insert(
          new_signs,
          vim.tbl_deep_extend("force", {
            id = first_note.id,
            lnum = first_note.position.new_line,
          }, base_sign)
        )
        discussion_line = first_note.position.new_line
        start_line = start_new_line
        end_line = end_new_line
      elseif first_note.position.line_range.start.type == "old" then
        table.insert(
          old_signs,
          vim.tbl_deep_extend("force", {
            id = first_note.id,
            lnum = first_note.position.old_line,
          }, base_sign)
        )
        discussion_line = first_note.position.old_line
        start_line = start_old_line
        end_line = end_old_line
      end
      -- Helper signs does not have specific ids currently.
      if state.settings.discussion_sign.helper_signs.enabled then
        local helper_signs = {}
        if start_line > end_line then
          start_line, end_line = end_line, start_line
        end
        for i = start_line, end_line do
          if i ~= discussion_line then
            local sign_name
            if i == start_line then
              sign_name = discussion_helper_sign_start
            elseif i == end_line then
              sign_name = discussion_helper_sign_end
            else
              sign_name = discussion_helper_sign_mid
            end
            table.insert(
              helper_signs,
              vim.tbl_deep_extend("keep", {
                name = sign_name,
                lnum = i,
              }, base_helper_sign)
            )
          end
        end
        if first_note.position.line_range.start.type == "new" then
          vim.list_extend(new_signs, helper_signs)
        elseif first_note.position.line_range.start.type == "old" then
          vim.list_extend(old_signs, helper_signs)
        end
      end
    else
      local sign = vim.tbl_deep_extend("force", {
        id = first_note.id,
      }, base_sign)
      if first_note.position.new_line ~= nil then
        table.insert(new_signs, vim.tbl_deep_extend("force", { lnum = first_note.position.new_line }, sign))
      end
      if first_note.position.old_line ~= nil then
        table.insert(old_signs, vim.tbl_deep_extend("force", { lnum = first_note.position.old_line }, sign))
      end
    end
  end
  vim.fn.sign_unplace(discussion_sign_name)
  reviewer.place_sign(old_signs, "old")
  reviewer.place_sign(new_signs, "new")
end

---Build note header from note.
---@param note Note
---@return string
M.build_note_header = function(note)
  return "@" .. note.author.username .. " " .. u.time_since(note.created_at)
end

---Refresh the diagnostics for the currently reviewed file
M.refresh_diagnostics = function()
  -- Keep in mind that diagnostic line numbers use 0-based indexing while line numbers use
  -- 1-based indexing
  local diagnostics = M.filter_discussions_for_signs_and_diagnostics()
  if diagnostics == nil then
    vim.diagnostic.reset(diagnostics_namespace)
    return
  end

  local new_diagnostics = {}
  local old_diagnostics = {}
  for _, discussion in ipairs(diagnostics) do
    local first_note = discussion.notes[1]
    local message = ""
    for _, note in ipairs(discussion.notes) do
      message = message .. M.build_note_header(note) .. "\n" .. note.body .. "\n"
    end

    local diagnostic = {
      message = message,
      col = 0,
      severity = state.settings.discussion_diagnostic.severity,
      user_data = { discussion_id = discussion.id, header = M.build_note_header(discussion.notes[1]) },
      source = "gitlab",
      code = state.settings.discussion_diagnostic.code,
    }
    if first_note.position.line_range ~= nil then
      -- Diagnostics for line range discussions are tricky - you need to set lnum to
      -- line number equal to note.position.new_line or note.position.old_line because that is
      -- only line where you can trigger the diagnostic show. This also need to be in sinc
      -- with the sign placement.
      local start_old_line, start_new_line = _parse_line_code(first_note.position.line_range.start.line_code)
      local end_old_line, end_new_line = _parse_line_code(first_note.position.line_range["end"].line_code)
      if first_note.position.line_range.start.type == "new" then
        local new_diagnostic
        if first_note.position.new_line == start_new_line then
          new_diagnostic = {
            lnum = start_new_line - 1,
            end_lnum = end_new_line - 1,
          }
        else
          new_diagnostic = {
            lnum = end_new_line - 1,
            end_lnum = start_new_line - 1,
          }
        end
        new_diagnostic = vim.tbl_deep_extend("force", new_diagnostic, diagnostic)
        table.insert(new_diagnostics, new_diagnostic)
      elseif first_note.position.line_range.start.type == "old" then
        local old_diagnostic
        if first_note.position.old_line == start_old_line then
          old_diagnostic = {
            lnum = start_old_line - 1,
            end_lnum = end_old_line - 1,
          }
        else
          old_diagnostic = {
            lnum = end_old_line - 1,
            end_lnum = start_old_line - 1,
          }
        end
        old_diagnostic = vim.tbl_deep_extend("force", old_diagnostic, diagnostic)
        table.insert(old_diagnostics, old_diagnostic)
      end
    else
      -- Diagnostics for single line discussions.
      if first_note.position.new_line ~= nil then
        local new_diagnostic = {
          lnum = first_note.position.new_line - 1,
        }
        new_diagnostic = vim.tbl_deep_extend("force", new_diagnostic, diagnostic)
        table.insert(new_diagnostics, new_diagnostic)
      end
      if first_note.position.old_line ~= nil then
        local old_diagnostic = {
          lnum = first_note.position.old_line - 1,
        }
        old_diagnostic = vim.tbl_deep_extend("force", old_diagnostic, diagnostic)
        table.insert(old_diagnostics, old_diagnostic)
      end
    end
  end

  vim.diagnostic.reset(diagnostics_namespace)
  reviewer.set_diagnostics(
    diagnostics_namespace,
    new_diagnostics,
    "new",
    state.settings.discussion_diagnostic.display_opts
  )
  reviewer.set_diagnostics(
    diagnostics_namespace,
    old_diagnostics,
    "old",
    state.settings.discussion_diagnostic.display_opts
  )
end

---Refresh discussion data, discussion signs and diagnostics
M.refresh_discussion_data = function()
  M.load_discussions(function()
    if state.settings.discussion_sign.enabled then
      M.refresh_signs()
    end
    if state.settings.discussion_diagnostic.enabled then
      M.refresh_diagnostics()
    end
  end)
end

---Define signs for discussions if not already defined
M.setup_signs = function()
  local discussion_sign = state.settings.discussion_sign
  local signs = {
    [discussion_sign_name] = discussion_sign.text,
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

---Initialize everything for discussions like setup of signs, callbacks for reviewer, etc.
M.initialize_discussions = function()
  M.setup_signs()
  M.setup_refresh_discussion_data_callback()
  M.setup_leave_reviewer_callback()
end

---Setup callback to refresh discussion data, discussion signs and diagnostics whenever the
---reviewed file changes.
M.setup_refresh_discussion_data_callback = function()
  reviewer.set_callback_for_file_changed(M.refresh_discussion_data)
end

---Clear all signs and diagnostics
M.clear_signs_and_discussions = function()
  vim.fn.sign_unplace(discussion_sign_name)
  vim.diagnostic.reset(diagnostics_namespace)
end

---Setup callback to clear signs and diagnostics whenever reviewer is left.
M.setup_leave_reviewer_callback = function()
  reviewer.set_callback_for_reviewer_leave(M.clear_signs_and_discussions)
end

M.refresh_discussion_tree = function()
  if M.layout_visible == false then
    return
  end

  if type(M.discussions) == "table" then
    M.rebuild_discussion_tree()
  end
  if type(M.unlinked_discussions) == "table" then
    M.rebuild_unlinked_discussion_tree()
  end

  M.switch_can_edit_bufs(true)
  M.add_empty_titles({
    { M.linked_section.bufnr, M.discussions, "No Discussions for this MR" },
    { M.unlinked_section.bufnr, M.unlinked_discussions, "No Notes (Unlinked Discussions) for this MR" },
  })
  M.switch_can_edit_bufs(false)
end

---Opens the discussion tree, sets the keybindings. It also
---creates the tree for notes (which are not linked to specific lines of code)
---@param callback function?
M.toggle = function(callback)
  if M.layout_visible then
    M.layout:unmount()
    M.layout_visible = false
    M.discussion_tree = nil
    M.linked_section = nil
    M.unlinked_section = nil
    return
  end

  local linked_section, unlinked_section, layout = M.create_layout()
  M.linked_section = linked_section
  M.unlinked_section = unlinked_section

  M.load_discussions(function()
    if type(M.discussions) ~= "table" and type(M.unlinked_discussions) ~= "table" then
      vim.notify("No discussions or notes for this MR", vim.log.levels.WARN)
      return
    end

    layout:mount()
    layout:show()

    M.layout = layout
    M.layout_visible = true
    M.layout_buf = layout.bufnr
    state.discussion_buf = layout.bufnr
    M.refresh_discussion_tree()
    if type(callback) == "function" then
      callback()
    end
  end)
end

---Move to the discussion tree at the discussion from diagnostic on current line.
M.move_to_discussion_tree = function()
  local current_line = vim.api.nvim_win_get_cursor(0)[1]
  local diagnostics = vim.diagnostic.get(0, { namespace = diagnostics_namespace, lnum = current_line - 1 })

  ---Function used to jump to the discussion tree after the menu selection.
  local jump_after_menu_selection = function(diagnostic)
    ---Function used to jump to the discussion tree after the discussion tree is opened.
    local jump_after_tree_opened = function()
      -- All diagnostics in `diagnotics_namespace` have diagnostic_id
      local discussion_id = diagnostic.user_data.discussion_id
      local discussion_node, line_number = M.discussion_tree:get_node("-" .. discussion_id)
      if discussion_node == {} or discussion_node == nil then
        vim.notify("Discussion not found", vim.log.levels.WARN)
        return
      end
      if not discussion_node:is_expanded() then
        for _, child in ipairs(discussion_node:get_child_ids()) do
          M.discussion_tree:get_node(child):expand()
        end
        discussion_node:expand()
      end
      M.discussion_tree:render()
      vim.api.nvim_win_set_cursor(M.linked_section.winid, { line_number, 0 })
      vim.api.nvim_set_current_win(M.linked_section.winid)
    end

    if not M.layout_visible then
      M.toggle(jump_after_tree_opened)
    else
      jump_after_tree_opened()
    end
  end

  if #diagnostics == 0 then
    vim.notify("No diagnostics for this line", vim.log.levels.WARN)
    return
  elseif #diagnostics > 1 then
    vim.ui.select(diagnostics, {
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
    jump_after_menu_selection(diagnostics[1])
  end
end

-- The reply popup will mount in a window when you trigger it (settings.discussion_tree.reply) when hovering over a node in the discussion tree.
M.reply = function(tree)
  local node = tree:get_node()
  local discussion_node = M.get_root_node(tree, node)
  local id = tostring(discussion_node.id)
  reply_popup:mount()
  state.set_popup_keymaps(reply_popup, M.send_reply(tree, id), miscellaneous.attach_file)
end

-- This function will send the reply to the Go API
M.send_reply = function(tree, discussion_id)
  return function(text)
    local body = { discussion_id = discussion_id, reply = text }
    job.run_job("/reply", "POST", body, function(data)
      u.notify("Sent reply!", vim.log.levels.INFO)
      M.add_reply_to_tree(tree, data.note, discussion_id)
    end)
  end
end

-- This function (settings.discussion_tree.delete_comment) will trigger a popup prompting you to delete the current comment
M.delete_comment = function(tree, unlinked)
  vim.ui.select({ "Confirm", "Cancel" }, {
    prompt = "Delete comment?",
  }, function(choice)
    if choice == "Confirm" then
      M.send_deletion(tree, unlinked)
    end
  end)
end

-- This function will actually send the deletion to Gitlab
-- when you make a selection, and re-render the tree
M.send_deletion = function(tree, unlinked)
  local current_node = tree:get_node()

  local note_node = M.get_note_node(tree, current_node)
  local root_node = M.get_root_node(tree, current_node)
  local note_id = note_node.is_root and root_node.root_note_id or note_node.id

  local body = { discussion_id = root_node.id, note_id = note_id }

  job.run_job("/comment", "DELETE", body, function(data)
    u.notify(data.message, vim.log.levels.INFO)
    if not note_node.is_root then
      tree:remove_node("-" .. note_id) -- Note is not a discussion root, safe to remove
      tree:render()
    else
      if unlinked then
        M.unlinked_discussions = u.remove_first_value(M.unlinked_discussions)
        M.rebuild_unlinked_discussion_tree()
      else
        M.discussions = u.remove_first_value(M.discussions)
        M.rebuild_discussion_tree()
      end
      M.switch_can_edit_bufs(true)
      M.add_empty_titles({
        { M.linked_section.bufnr, M.discussions, "No Discussions for this MR" },
        { M.unlinked_section.bufnr, M.unlinked_discussions, "No Notes (Unlinked Discussions) for this MR" },
      })
      M.switch_can_edit_bufs(false)
    end
  end)
end

-- This function (settings.discussion_tree.edit_comment) will open the edit popup for the current comment in the discussion tree
M.edit_comment = function(tree, unlinked)
  local current_node = tree:get_node()
  local note_node = M.get_note_node(tree, current_node)
  local root_node = M.get_root_node(tree, current_node)

  edit_popup:mount()

  local lines = {} -- Gather all lines from immediate children that aren't note nodes
  local children_ids = note_node:get_child_ids()
  for _, child_id in ipairs(children_ids) do
    local child_node = tree:get_node(child_id)
    if not child_node:has_children() then
      local line = tree:get_node(child_id).text
      table.insert(lines, line)
    end
  end

  local currentBuffer = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(currentBuffer, 0, -1, false, lines)
  state.set_popup_keymaps(
    edit_popup,
    M.send_edits(tostring(root_node.id), note_node.root_note_id or note_node.id, unlinked)
  )
end

-- This function sends the edited comment to the Go server
M.send_edits = function(discussion_id, note_id, unlinked)
  return function(text)
    local body = {
      discussion_id = discussion_id,
      note_id = note_id,
      comment = text,
    }
    job.run_job("/comment", "PATCH", body, function(data)
      u.notify(data.message, vim.log.levels.INFO)
      if unlinked then
        M.unlinked_discussions = M.replace_text(M.unlinked_discussions, discussion_id, note_id, text)
        M.rebuild_unlinked_discussion_tree()
      else
        M.discussions = M.replace_text(M.discussions, discussion_id, note_id, text)
        M.rebuild_discussion_tree()
      end
    end)
  end
end

-- This function (settings.discussion_tree.toggle_discussion_resolved) will toggle the resolved status of the current discussion and send the change to the Go server
M.toggle_discussion_resolved = function(tree)
  local note = tree:get_node()
  if not note or not note.resolvable then
    return
  end

  local body = {
    discussion_id = note.id,
    resolved = not note.resolved,
  }

  job.run_job("/discussions/resolve", "PUT", body, function(data)
    u.notify(data.message, vim.log.levels.INFO)
    M.redraw_resolved_status(tree, note, not note.resolved)
  end)
end

-- This function (settings.discussion_tree.jump_to_reviewer) will jump the cursor to the reviewer's location associated with the note. The implementation depends on the reviewer
M.jump_to_reviewer = function(tree)
  local file_name, new_line, old_line, error = M.get_note_location(tree)
  if error ~= nil then
    u.notify(error, vim.log.levels.ERROR)
    return
  end
  reviewer.jump(file_name, new_line, old_line)
end

-- This function (settings.discussion_tree.jump_to_file) will jump to the file changed in a new tab
M.jump_to_file = function(tree)
  local file_name, new_line, old_line, error = M.get_note_location(tree)
  if error ~= nil then
    u.notify(error, vim.log.levels.ERROR)
    return
  end
  vim.cmd.tabnew()
  u.jump_to_file(file_name, (new_line or old_line))
end

-- This function (settings.discussion_tree.toggle_node) expands/collapses the current node and its children
M.toggle_node = function(tree)
  local node = tree:get_node()
  if node == nil then
    return
  end
  local children = node:get_child_ids()
  if node == nil then
    return
  end
  if node:is_expanded() then
    node:collapse()
    if M.is_node_note(node) then
      for _, child in ipairs(children) do
        tree:get_node(child):collapse()
      end
    end
  else
    if M.is_node_note(node) then
      for _, child in ipairs(children) do
        tree:get_node(child):expand()
      end
    end
    node:expand()
  end

  tree:render()
end

--
-- 🌲 Helper Functions
--
---Inspired by default func https://github.com/MunifTanjim/nui.nvim/blob/main/lua/nui/tree/util.lua#L38
local function nui_tree_prepare_node(node)
  if not node.text then
    error("missing node.text")
  end

  local texts = node.text

  if type(node.text) ~= "table" or node.text.content then
    texts = { node.text }
  end

  local lines = {}

  for i, text in ipairs(texts) do
    local line = NuiLine()

    line:append(string.rep("  ", node._depth - 1))

    if i == 1 and node:has_children() then
      line:append(node:is_expanded() and " " or " ")
      if node.icon then
        line:append(node.icon .. " ", node.icon_hl)
      end
    else
      line:append("  ")
    end

    line:append(text, node.text_hl)

    table.insert(lines, line)
  end

  return lines
end

M.rebuild_discussion_tree = function()
  M.switch_can_edit_bufs(true)
  vim.api.nvim_buf_set_lines(M.linked_section.bufnr, 0, -1, false, {})
  local discussion_tree_nodes = discussions_tree.add_discussions_to_table(M.discussions, false)
  local discussion_tree =
    NuiTree({ nodes = discussion_tree_nodes, bufnr = M.linked_section.bufnr, prepare_node = nui_tree_prepare_node })
  discussion_tree:render()
  M.set_tree_keymaps(discussion_tree, M.linked_section.bufnr, false)
  M.discussion_tree = discussion_tree
  M.switch_can_edit_bufs(false)
  vim.api.nvim_set_option_value("filetype", "gitlab", { buf = M.linked_section.bufnr })
end

M.rebuild_unlinked_discussion_tree = function()
  M.switch_can_edit_bufs(true)
  vim.api.nvim_buf_set_lines(M.unlinked_section.bufnr, 0, -1, false, {})
  local unlinked_discussion_tree_nodes = discussions_tree.add_discussions_to_table(M.unlinked_discussions, true)
  local unlinked_discussion_tree = NuiTree({
    nodes = unlinked_discussion_tree_nodes,
    bufnr = M.unlinked_section.bufnr,
    prepare_node = nui_tree_prepare_node,
  })
  unlinked_discussion_tree:render()
  M.set_tree_keymaps(unlinked_discussion_tree, M.unlinked_section.bufnr, true)
  M.unlinked_discussion_tree = unlinked_discussion_tree
  M.switch_can_edit_bufs(false)
  vim.api.nvim_set_option_value("filetype", "gitlab", { buf = M.unlinked_section.bufnr })
end

M.switch_can_edit_bufs = function(bool)
  u.switch_can_edit_buf(M.unlinked_section.bufnr, bool)
  u.switch_can_edit_buf(M.linked_section.bufnr, bool)
end

M.add_discussion = function(arg)
  local discussion = arg.data.discussion
  if arg.unlinked then
    if type(M.unlinked_discussions) ~= "table" then
      M.unlinked_discussions = {}
    end
    table.insert(M.unlinked_discussions, 1, discussion)
    if M.unlinked_section ~= nil then
      M.rebuild_unlinked_discussion_tree()
    end
    return
  end
  if type(M.discussions) ~= "table" then
    M.discussions = {}
  end
  table.insert(M.discussions, 1, discussion)
  if M.linked_section ~= nil then
    M.rebuild_discussion_tree()
  end
end

M.create_layout = function()
  local linked_section = Split({ enter = true })
  local unlinked_section = Split({})

  local position = state.settings.discussion_tree.position
  local size = state.settings.discussion_tree.size
  local relative = state.settings.discussion_tree.relative

  local layout = Layout(
    {
      position = position,
      size = size,
      relative = relative,
    },
    Layout.Box({
      Layout.Box(linked_section, { size = "50%" }),
      Layout.Box(unlinked_section, { size = "50%" }),
    }, { dir = (position == "left" and "col" or "row") })
  )

  return linked_section, unlinked_section, layout
end

M.add_empty_titles = function(args)
  local ns_id = vim.api.nvim_create_namespace("GitlabNamespace")
  vim.cmd("highlight default TitleHighlight guifg=#787878")
  for _, section in ipairs(args) do
    local bufnr, data, title = section[1], section[2], section[3]
    if type(data) ~= "table" or #data == 0 then
      vim.api.nvim_buf_set_lines(bufnr, 0, 1, false, { title })
      local linnr = 1
      vim.api.nvim_buf_set_extmark(
        bufnr,
        ns_id,
        linnr - 1,
        0,
        { end_row = linnr - 1, end_col = string.len(title), hl_group = "TitleHighlight" }
      )
    end
  end
end

---Check if type of node is note or note body
---@param node NuiTree.Node?
---@return boolean
M.is_node_note = function(node)
  if node and (node.type == "note_body" or node.type == "note") then
    return true
  else
    return false
  end
end

---Check if type of current node is note or note body
---@param tree NuiTree
---@return boolean
M.is_current_node_note = function(tree)
  return M.is_node_note(tree:get_node())
end

M.set_tree_keymaps = function(tree, bufnr, unlinked)
  vim.keymap.set("n", state.settings.discussion_tree.edit_comment, function()
    if M.is_current_node_note(tree) then
      M.edit_comment(tree, unlinked)
    end
  end, { buffer = bufnr })
  vim.keymap.set("n", state.settings.discussion_tree.delete_comment, function()
    if M.is_current_node_note(tree) then
      M.delete_comment(tree, unlinked)
    end
  end, { buffer = bufnr })
  vim.keymap.set("n", state.settings.discussion_tree.toggle_resolved, function()
    if M.is_current_node_note(tree) then
      M.toggle_discussion_resolved(tree)
    end
  end, { buffer = bufnr })
  vim.keymap.set("n", state.settings.discussion_tree.toggle_node, function()
    M.toggle_node(tree)
  end, { buffer = bufnr })
  vim.keymap.set("n", state.settings.discussion_tree.reply, function()
    if M.is_current_node_note(tree) then
      M.reply(tree)
    end
  end, { buffer = bufnr })

  if not unlinked then
    vim.keymap.set("n", state.settings.discussion_tree.jump_to_file, function()
      if M.is_current_node_note(tree) then
        M.jump_to_file(tree)
      end
    end, { buffer = bufnr })
    vim.keymap.set("n", state.settings.discussion_tree.jump_to_reviewer, function()
      if M.is_current_node_note(tree) then
        M.jump_to_reviewer(tree)
      end
    end, { buffer = bufnr })
  end
end

M.redraw_resolved_status = function(tree, note, mark_resolved)
  local current_text = tree.nodes.by_id["-" .. note.id].text
  local target = mark_resolved and "resolved" or "unresolved"
  local current = mark_resolved and "unresolved" or "resolved"

  local function set_property(key, val)
    tree.nodes.by_id["-" .. note.id][key] = val
  end

  local has_symbol = function(s)
    return state.settings.discussion_tree[s] ~= nil and state.settings.discussion_tree[s] ~= ""
  end

  set_property("resolved", mark_resolved)

  if not has_symbol(current) and not has_symbol(target) then
    return
  end

  if not has_symbol(current) and has_symbol(target) then
    set_property("text", (current_text .. " " .. state.settings.discussion_tree[target]))
  elseif has_symbol(current) and not has_symbol(target) then
    set_property("text", u.remove_last_chunk(current_text))
  else
    set_property("text", (u.remove_last_chunk(current_text) .. " " .. state.settings.discussion_tree[target]))
  end

  tree:render()
end

M.replace_text = function(data, discussion_id, note_id, text)
  for i, discussion in ipairs(data) do
    if discussion.id == discussion_id then
      for j, note in ipairs(discussion.notes) do
        if note.id == note_id then
          data[i].notes[j].body = text
          return data
        end
      end
    end
  end
end

---Get root node
---@param tree NuiTree
---@param node NuiTree.Node?
---@return NuiTree.Node?
M.get_root_node = function(tree, node)
  if not node then
    return nil
  end
  if node.type == "note_body" or node.type == "note" and not node.is_root then
    local parent_id = node:get_parent_id()
    return M.get_root_node(tree, tree:get_node(parent_id))
  elseif node.is_root then
    return node
  end
end

---Get note node
---@param tree NuiTree
---@param node NuiTree.Node?
---@return NuiTree.Node?
M.get_note_node = function(tree, node)
  if not node then
    return nil
  end

  if node.type == "note_body" then
    local parent_id = node:get_parent_id()
    if parent_id == nil then
      return node
    end
    return M.get_note_node(tree, tree:get_node(parent_id))
  elseif node.type == "note" then
    return node
  end
end

M.add_reply_to_tree = function(tree, note, discussion_id)
  local note_node = M.build_note(note)
  note_node:expand()
  tree:add_node(note_node, discussion_id and ("-" .. discussion_id) or nil)
  tree:render()
end

---Get note location
---@param tree NuiTree
M.get_note_location = function(tree)
  local node = tree:get_node()
  if node == nil then
    return nil, nil, nil, "Could not get node"
  end
  local discussion_node = M.get_root_node(tree, node)
  if discussion_node == nil then
    return nil, nil, nil, "Could not get discussion node"
  end
  return discussion_node.file_name, discussion_node.new_line, discussion_node.old_line
end

return M
