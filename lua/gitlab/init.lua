local Job     = require("plenary.job")
local popup   = require("gitlab.utils.popup")
local u       = require("gitlab.utils")
local M       = {}

local binPath = vim.fn.stdpath("data") .. "/lazy/gitlab.nvim"
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
M.setup   = function(args)
  local binExists = io.open(bin, "r")
  if not binExists then
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


  local data = {}
  Job:new({
    command = bin,
    args = { "projectInfo" },
    on_stdout = function(_, line)
      table.insert(data, line)
    end,
    on_stderr = printError,
    on_exit = function()
      if data[1] ~= nil then
        local parsed = vim.json.decode(data[1])
        M.projectInfo = parsed[1]
      end
    end,
  }):start()
end

M.review  = function()
  local isDiff = vim.fn.getwinvar(nil, "&diff")
  local bufName = vim.api.nvim_buf_get_name(0)
  local hasBaseBranch = u.branch_exists(M.BASE_BRANCH)
  if not hasBaseBranch then
    require("notify")('No ' .. M.BASE_BRANCH .. ' branch, cannot review!', "error")
    return
  end
  if isDiff ~= 0 or u.string_starts(bufName, "diff") then
    return
  else
    vim.cmd.DiffviewOpen(M.BASE_BRANCH)
    u.press_enter()
  end
end

-- Approves the merge request
M.approve = function()
  Job:new({
    command = bin,
    args = { "approve", M.projectInfo.id },
    on_stdout = printSuccess,
    on_stderr = printError
  }):start()
end

-- Revokes approval for the current merge request
M.revoke  = function()
  Job:new({
    command = bin,
    args = { "revoke", M.projectInfo.id },
    on_stdout = printSuccess,
    on_stderr = printError
  }):start()
end

-- Opens the popup window
M.comment = function()
  popup:mount()
end


-- This function invokes our binary and sends the text to Gitlab. The text comes from the after/ftplugin/gitlab.lua file
M.sendComment = function(text)
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
