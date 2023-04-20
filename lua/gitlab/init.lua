local Job     = require("plenary.job")
local comment = require("gitlab.utils.comment")
local summary = require("gitlab.utils.summary")
local u       = require("gitlab.utils")
local M       = {}

local binPath = vim.fn.stdpath("data") .. "/lazy/gitlab"
local bin     = binPath .. "/bin"

M.PROJECT_ID  = nil
M.info        = {}

local function printSuccess(_, line)
  if line ~= nil and line ~= "" then
    require("notify")(line, "info")
  end
end

local function printError(_, line)
  if line ~= nil and line ~= "" then
    require("notify")(line, "error")
  end
end

-- Builds the Go binary, initializes the plugin, fetches MR info
local projectData = {}
M.setup           = function(args)
  if args.dev == true then
    -- This is for the developer (harrisoncramer) only.
    binPath = vim.fn.stdpath("config") .. "/dev-plugins/gitlab"
    bin = binPath .. "/bin"
  end
  local binExists = io.open(bin, "r")
  if not binExists or args.dev == true then
    local command = string.format("cd %s && make", binPath)
    local installCode = os.execute(command)
    if installCode ~= 0 then
      require("notify")("Could not install gitlab.nvim! Do you have Go installed?", "error")
      return
    end
  end

  if args.project_id == nil then
    error("No project ID provided!")
  end
  M.PROJECT_ID = args.project_id

  if args.base_branch == nil then
    M.BASE_BRANCH = "main"
  else
    M.BASE_BRANCH = args.base_branch
  end

  Job:new({
    command = bin,
    args = { "info", M.PROJECT_ID },
    on_stdout = function(_, line)
      table.insert(projectData, line)
    end,
    on_stderr = printError,
    on_exit = function()
      if projectData[1] ~= nil then
        local parsed = vim.json.decode(projectData[1])
        if parsed == nil then
          require("notify")("Could not get project data", "error")
        else
          M.info = parsed
        end
      end
    end,
  }):start()
end

-- Provides the description and title of the MR for reading (fetched immediately on setup)
M.summary         = function()
  if u.baseInvalid() then return end
  summary:mount()
  local currentBuffer = vim.api.nvim_get_current_buf()
  local title = M.info.title
  local description = M.info.description
  local lines = {}
  for line in description:gmatch("[^\n]+") do
    table.insert(lines, line)
    table.insert(lines, "")
  end
  vim.schedule(function()
    vim.api.nvim_buf_set_lines(currentBuffer, 0, -1, false, lines)
    vim.api.nvim_buf_set_option(currentBuffer, "modifiable", false)
    summary.border:set_text("top", title, "center")
    vim.keymap.set('n', '<Esc>', function() exit(summary) end, { buffer = true })
    vim.keymap.set('n', ':', '', { buffer = true })
  end)
end

-- Opens diffview of the current MR
M.review          = function()
  if u.baseInvalid() then return end
  vim.cmd.DiffviewOpen(M.BASE_BRANCH)
  u.press_enter()
end

local mrData      = {}
local function exit(popup)
  popup:unmount()
end

-- Places all of the comments into a readable list
M.listComments = function()
  if u.baseInvalid() then return end
  Job:new({
    command = bin,
    args = { "listComments", M.PROJECT_ID },
    on_stdout = function(_, line)
      local comments = vim.json.decode(line)
      M.comments = comments
      vim.schedule(function()
        vim.cmd.tabnew()
        local buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_option(buf, 'filetype', 'markdown')
        vim.api.nvim_set_current_buf(buf)
        vim.keymap.set('n', 'O', function()
          local current_line = vim.api.nvim_get_current_line()
          local _, __, commentId = string.find(current_line, "%((%d+)%)")
          local match = u.findValueById(M.comments, commentId)
          if match == nil then
            return
          end
          local file = match.position.new_path
          local line = match.position.new_line
          u.jump_to_file(file, line)
          u.add_comment_sign(line)
        end, { buffer = true })
        if comments == nil then
          require("notify")("No comments found", "warn")
        else
          for _, c in ipairs(comments) do
            local cTable = {}
            table.insert(cTable,
              "# @" .. c.author.username .. " on " .. u.formatDate(c.created_at) .. " (" .. c.id .. ")")
            for bodyLine in c.body:gmatch("[^\n]+") do
              table.insert(cTable, bodyLine)
            end
            table.insert(cTable, "")
            table.insert(cTable, "")
            local line_count = vim.api.nvim_buf_line_count(buf)
            if line_count == 1 then line_count = -1 end
            vim.api.nvim_buf_set_lines(buf, line_count + 1, line_count + #cTable + 3, false, cTable)
          end
          vim.api.nvim_buf_set_option(buf, 'modifiable', false)
        end
      end)
    end,
    on_stderr = printError,
  }):start()
end

-- Approves the current merge request
M.approve      = function()
  if u.baseInvalid() then return end
  Job:new({
    command = bin,
    args = { "approve", M.PROJECT_ID },
    on_stdout = printSuccess,
    on_stderr = printError
  }):start()
end

-- Revokes approval for the current merge request
M.revoke       = function()
  if u.baseInvalid() then return end
  Job:new({
    command = bin,
    args = { "revoke", M.PROJECT_ID },
    on_stdout = printSuccess,
    on_stderr = printError
  }):start()
end

-- Opens the popup window to send a comment
M.comment      = function()
  if u.baseInvalid() then return end
  comment:mount()
  vim.keymap.set('n', '<Esc>', function() exit(comment) end, { buffer = true })
  vim.keymap.set('n', ':', '', { buffer = true })
  vim.keymap.set('n', '<leader>s', function()
    local text = u.get_buffer_text(comment.bufnr)
    comment:unmount()
    M.sendComment(text)
  end, { buffer = true })
end

-- Sends the comment to Gitlab
M.sendComment  = function(text)
  if u.baseInvalid() then return end
  local relative_file_path = u.get_relative_file_path()
  local current_line_number = u.get_current_line_number()
  Job:new({
    command = bin,
    args = {
      "comment",
      M.PROJECT_ID,
      current_line_number,
      relative_file_path,
      text,
    },
    on_stdout = printSuccess,
    on_stderr = printError
  }):start()
end

return M
