local Job     = require("plenary.job")
local comment = require("gitlab.utils.comment")
local summary = require("gitlab.utils.summary")
local u       = require("gitlab.utils")
local M       = {}

local binPath = vim.fn.stdpath("data") .. "/lazy/gitlab"
local bin     = binPath .. "/bin"

M.PROJECT_ID  = nil
M.projectInfo = {}

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

-- Builds the Go binary, and initializes the plugin so that we can communicate with Gitlab's API
local projectData = {}
M.setup           = function(args)
  if args.dev == true then
    -- This is for the developer (harrisoncramer) only.
    binPath = vim.fn.stdpath("config") .. "/dev-plugins/gitlab"
    bin = binPath .. "/bin"
  end
  local binExists = io.open(bin, "r")
  if not binExists or args.dev == true then
    local command = string.format("cd %s && go build -o bin ./cmd/main.go", binPath)
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
    args = { "projectInfo", M.PROJECT_ID },
    on_stdout = function(_, line)
      table.insert(projectData, line)
    end,
    on_stderr = printError,
    on_exit = function()
      if projectData[1] ~= nil then
        local parsed = vim.json.decode(projectData[1])
        M.projectInfo = parsed[1]
      end
    end,
  }):start()
end

M.review          = function()
  if u.baseInvalid() then return end
  vim.cmd.DiffviewOpen(M.BASE_BRANCH)
  u.press_enter()
end

local mrData      = {}
local function exit(popup)
  popup:unmount()
end
M.read    = function()
  if u.baseInvalid() then return end
  summary:mount()
  local currentBuffer = vim.api.nvim_get_current_buf()
  Job:new({
    command = bin,
    args = { "read", M.projectInfo.id },
    on_stderr = printError,
    on_stdout = function(_, line)
      table.insert(mrData, line)
    end,
    on_exit = function()
      if mrData[1] ~= nil then
        local parsed = vim.json.decode(mrData[1])
        local title = parsed.title
        local description = parsed.description
        -- Use string.gmatch to iterate over matches of pattern "\n" (newline)
        local lines = {}
        for line in description:gmatch("[^\n]+") do
          table.insert(lines, line)
          table.insert(lines, "")
        end
        vim.schedule(function()
          -- Preprocess the replacement string to escape newline characters
          vim.api.nvim_buf_set_lines(currentBuffer, 0, -1, false, lines)
          vim.api.nvim_buf_set_option(currentBuffer, "modifiable", false)
          summary.border:set_text("top", title, "center")
          vim.keymap.set('n', '<Esc>', function() exit(summary) end, { buffer = true })
          vim.keymap.set('n', ':', '', { buffer = true })
        end)
      end
    end,
  }):start()
end

-- Approves the merge request
M.approve = function()
  if u.baseInvalid() then return end
  Job:new({
    command = bin,
    args = { "approve", M.projectInfo.id },
    on_stdout = printSuccess,
    on_stderr = printError
  }):start()
end

-- Revokes approval for the current merge request
M.revoke  = function()
  if u.baseInvalid() then return end
  Job:new({
    command = bin,
    args = { "revoke", M.projectInfo.id },
    on_stdout = printSuccess,
    on_stderr = printError
  }):start()
end

-- Opens the popup window
local function send()
  local text = u.get_buffer_text(comment.bufnr)
  comment:unmount()
  M.sendComment(text)
end

M.comment     = function()
  if u.baseInvalid() then return end
  comment:mount()
  vim.keymap.set('n', '<Esc>', function() exit(comment) end, { buffer = true })
  vim.keymap.set('n', ':', '', { buffer = true })
  vim.keymap.set('n', '<leader>s', send, { buffer = true })
end

-- This function invokes our binary and sends the text to Gitlab. The text comes from the after/ftplugin/gitlab.lua file
M.sendComment = function(text)
  if u.baseInvalid() then return end
  local relative_file_path = u.get_relative_file_path()
  local current_line_number = u.get_current_line_number()
  Job:new({
    command = bin,
    args = {
      "comment",
      M.projectInfo.id,
      current_line_number,
      relative_file_path,
      text,
    },
    on_stdout = printSuccess,
    on_stderr = printError
  }):start()
end

return M
