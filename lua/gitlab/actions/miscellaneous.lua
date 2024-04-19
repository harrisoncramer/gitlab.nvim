local state = require("gitlab.state")
local List = require("gitlab.utils.list")
local reviewer = require("gitlab.reviewer")
local git = require("gitlab.git")
local u = require("gitlab.utils")
local job = require("gitlab.job")
local M = {}

M.attach_file = function()
  local attachment_dir = state.settings.attachment_dir
  if not attachment_dir or attachment_dir == "" then
    u.notify("Must provide valid attachment_dir in plugin setup", vim.log.levels.ERROR)
    return
  end

  local files = u.list_files_in_folder(attachment_dir)

  if files == nil then
    u.notify(string.format("Could not list files in %s", attachment_dir), vim.log.levels.ERROR)
    return
  end

  vim.ui.select(files, {
    prompt = "Choose attachment",
  }, function(choice)
    if not choice then
      return
    end
    local full_path = attachment_dir .. u.path_separator .. choice
    local body = { file_path = full_path, file_name = choice }
    job.run_job("/attachment", "POST", body, function(data)
      local markdown = data.markdown
      local current_line = u.get_current_line_number()
      local bufnr = vim.api.nvim_get_current_buf()
      vim.api.nvim_buf_set_lines(bufnr, current_line - 1, current_line, false, { markdown })
    end)
  end)
end

---@class SwitchOpts
---@field open_reviewer boolean

---Opens up a select menu that lets you choose a different merge request.
---@param opts SwitchOpts|nil
M.choose_merge_request = function(opts)
  if not git.has_clean_tree() then
    u.notify("Your local branch has changes, please stash or commit and push", vim.log.levels.ERROR)
    return
  end

  if opts == nil then
    opts = state.settings.choose_merge_request
  end

  local mrs = List.new(state.MERGE_REQUESTS)

  local titles = mrs:map(function(mr)
    return mr.title
  end)
  vim.ui.select(titles, {
    prompt = "Choose Merge Request",
  }, function(choice)
    if not choice then
      return
    end

    local mr = mrs:find(function(x)
      return x.title == choice
    end)

    if mr == nil then
      u.notify("Something went wrong choosing the branch", vim.log.levels.ERROR)
      return
    end

    if reviewer.is_open then
      reviewer.close()
    end

    vim.schedule(function()
      local err = git.switch_branch(mr.source_branch)
      if err ~= "" then
        u.notify(err, vim.log.levels.ERROR)
        return
      end

      vim.schedule(function()
        require("gitlab.server").restart(function()
          if opts.open_reviewer then
            require("gitlab").review()
          end
        end)
      end)
    end)
  end)
end

M.editable_popup_opts = {
  save_to_temp_register = true,
}

-- Get the index of the next popup when cycling forward
local function next_index(i, n, count)
  count = count > 0 and count or 1
  for _ = 1, count do
    if i < n then
      i = i + 1
    elseif i == n then
      i = 1
    end
  end
  return i
end

---Get the index of the previous popup when cycling backward
---@param i integer The current index
---@param n integer The total number of popups
---@param count integer The count used with the keymap (replaced with 1 if no count was given)
local function prev_index(i, n, count)
  count = count > 0 and count or 1
  for _ = 1, count do
    if i > 1 then
      i = i - 1
    elseif i == 1 then
      i = n
    end
  end
  return i
end

---Setup keymaps for cycling popups. The keymap accepts count.
---@param popups table Table of Popups
M.set_cycle_popups_keymaps = function(popups)
  local number_of_popups = #popups
  for i, popup in ipairs(popups) do
    popup:map("n", state.settings.popup.keymaps.next_field, function()
      vim.api.nvim_set_current_win(popups[next_index(i, number_of_popups, vim.v.count)].winid)
    end, { desc = "Go to next field (accepts count)" })
    popup:map("n", state.settings.popup.keymaps.prev_field, function()
      vim.api.nvim_set_current_win(popups[prev_index(i, number_of_popups, vim.v.count)].winid)
    end, { desc = "Go to previous field (accepts count)" })
  end
end

---Toggle the value in a "Boolean buffer"
M.toggle_bool = function()
  local bufnr = vim.api.nvim_get_current_buf()
  local current_val = u.get_buffer_text(bufnr)
  vim.schedule(function()
    u.switch_can_edit_buf(bufnr, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { u.toggle_string_bool(current_val) })
    u.switch_can_edit_buf(bufnr, false)
  end)
end

return M
