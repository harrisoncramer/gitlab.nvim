local List = require("gitlab.utils.list")
local u = require("gitlab.utils")
local state = require("gitlab.state")
local M = {}

---@class Hunk
---@field old_line integer
---@field old_range integer
---@field new_line integer
---@field new_range integer

---@class HunksAndDiff
---@field hunks Hunk[] list of hunks
---@field all_diff_output table The data from the git diff command

---Turn hunk line into Lua table
---@param line table
---@return Hunk|nil
M.parse_possible_hunk_headers = function(line)
  if line:sub(1, 2) == "@@" then
    -- match:
    --  @@ -23 +23 @@ ...
    --  @@ -23,0 +23 @@ ...
    --  @@ -41,0 +42,4 @@ ...
    local old_start, old_range, new_start, new_range = line:match("@@+ %-(%d+),?(%d*) %+(%d+),?(%d*) @@+")

    return {
      old_line = tonumber(old_start),
      old_range = tonumber(old_range) or 0,
      new_line = tonumber(new_start),
      new_range = tonumber(new_range) or 0,
    }
  end
end
---@param linnr number
---@param hunk Hunk
---@param all_diff_output table
---@return boolean
local line_was_removed = function(linnr, hunk, all_diff_output)
  for matching_line_index, line in ipairs(all_diff_output) do
    local found_hunk = M.parse_possible_hunk_headers(line)
    if found_hunk ~= nil and vim.deep_equal(found_hunk, hunk) then
      -- We found a matching hunk, now we need to iterate over the lines from the raw diff output
      -- at that hunk until we reach the line we are looking for. When the indexes match we check
      -- to see if that line is deleted or not.
      for hunk_line_index = found_hunk.old_line, hunk.old_line + hunk.old_range, 1 do
        local line_content = all_diff_output[matching_line_index + 1]
        if hunk_line_index == linnr then
          if string.match(line_content, "^%-") then
            return true
          end
        end
      end
    end
  end
  return false
end

---@param linnr number
---@param hunk Hunk
---@param all_diff_output table
---@return boolean
local line_was_added = function(linnr, hunk, all_diff_output)
  for matching_line_index, line in ipairs(all_diff_output) do
    local found_hunk = M.parse_possible_hunk_headers(line)
    if found_hunk ~= nil and vim.deep_equal(found_hunk, hunk) then
      -- Parse the lines from the hunk and return only the added lines
      local hunk_lines = {}
      local i = 1
      local line_content = all_diff_output[matching_line_index + i]
      while line_content ~= nil and line_content:sub(1, 2) ~= "@@" do
        if string.match(line_content, "^%+") then
          table.insert(hunk_lines, line_content)
        end
        i = i + 1
        line_content = all_diff_output[matching_line_index + i]
      end

      -- We are only looking at added lines in the changed hunk to see if their index
      -- matches the index of a line that was added
      local starting_index = found_hunk.new_line - 1 -- The "+j" will add one
      for j, _ in ipairs(hunk_lines) do
        if (starting_index + j) == linnr then
          return true
        end
      end
    end
  end
  return false
end

---Parse git diff hunks.
---@param base_sha string Git base SHA of merge request.
---@return HunksAndDiff
local parse_hunks_and_diff = function(base_sha)
  local hunks = {}
  local all_diff_output = {}

  local reviewer = require("gitlab.reviewer")
  local cmd = {
    "diff",
    "--minimal",
    "--unified=0",
    "--no-color",
    base_sha,
    "--",
    reviewer.get_current_file_oldpath(),
    reviewer.get_current_file_path(),
  }

  local Job = require("plenary.job")
  local diff_job = Job:new({
    command = "git",
    args = cmd,
    on_exit = function(j, return_code)
      if return_code == 0 then
        all_diff_output = j:result()
        for _, line in ipairs(all_diff_output) do
          local hunk = M.parse_possible_hunk_headers(line)
          if hunk ~= nil then
            table.insert(hunks, hunk)
          end
        end
      else
        M.notify("Failed to get git diff: " .. j:stderr(), vim.log.levels.WARN)
      end
    end,
  })

  diff_job:sync()

  return { hunks = hunks, all_diff_output = all_diff_output }
end

-- Parses the lines from a diff and returns the
-- index of the next hunk, when provided an initial index
---@param lines table
---@param i integer
---@return integer|nil
local next_hunk_index = function(lines, i)
  for j, line in ipairs(lines) do
    local hunk = M.parse_possible_hunk_headers(line)
    if hunk ~= nil and j > i then
      return j
    end
  end
  return nil
end

--- Processes the number of changes until the target is reached. This returns
--- a negative or positive number indicating the number of lines in the hunk
--- that have been added or removed prior to the target line
---@param line_number number
---@param hunk Hunk
---@param lines table
---@return integer
local net_changed_in_hunk_before_line = function(line_number, hunk, lines)
  local net_lines = 0
  local current_line_old = hunk.old_line

  for _, line in ipairs(lines) do
    if line:sub(1, 1) == "-" then
      if current_line_old < line_number then
        net_lines = net_lines - 1
      end
      current_line_old = current_line_old + 1
    elseif line:sub(1, 1) == "+" then
      if current_line_old < line_number then
        net_lines = net_lines + 1
      end
    else
      current_line_old = current_line_old + 1
    end
  end

  return net_lines
end

---Counts the total number of changes in a set of lines, can be positive if added lines or negative if removed lines
---@param lines table
---@return integer
local count_changes = function(lines)
  local total = 0
  for _, line in ipairs(lines) do
    if line:match("^%+") then
      total = total + 1
    else
      total = total - 1
    end
  end
  return total
end

---@param new_line number|nil
---@param hunks Hunk[]
---@param all_diff_output table
---@return string|nil
local function get_modification_type_from_new_sha(new_line, hunks, all_diff_output)
  if new_line == nil then
    return nil
  end
  return List.new(hunks):find(function(hunk)
    local new_line_end = hunk.new_line + hunk.new_range - (hunk.new_range > 0 and 1 or 0)
    local in_new_range = new_line >= hunk.new_line and new_line <= new_line_end
    local is_range_zero = hunk.new_range == 0 and hunk.old_range == 0
    return in_new_range and (is_range_zero or line_was_added(new_line, hunk, all_diff_output))
  end) and "added" or "bad_file_unmodified"
end

---@param old_line number|nil
---@param new_line number|nil
---@param hunks Hunk[]
---@param all_diff_output table
---@return string|nil
local function get_modification_type_from_old_sha(old_line, new_line, hunks, all_diff_output)
  if old_line == nil then
    return nil
  end

  return List.new(hunks):find(function(hunk)
    local old_line_end = hunk.old_line + hunk.old_range - (hunk.old_range > 0 and 1 or 0)
    local new_line_end = hunk.new_line + hunk.new_range - (hunk.new_range > 0 and 1 or 0)
    local in_old_range = old_line >= hunk.old_line and old_line <= old_line_end
    local in_new_range = new_line >= hunk.new_line and new_line <= new_line_end
    return (in_old_range or in_new_range) and line_was_removed(old_line, hunk, all_diff_output)
  end) and "deleted" or "unmodified"
end

---Returns whether the comment is on a deleted line, added line, or unmodified line.
---This is in order to build the payload for Gitlab correctly by setting the old line and new line.
---@param old_line number|nil
---@param new_line number|nil
---@param is_current_sha_focused boolean
---@return string|nil
function M.get_modification_type(old_line, new_line, is_current_sha_focused)
  local hunk_and_diff_data = parse_hunks_and_diff(state.INFO.diff_refs.base_sha)
  if hunk_and_diff_data.hunks == nil then
    return
  end

  local hunks = hunk_and_diff_data.hunks
  local all_diff_output = hunk_and_diff_data.all_diff_output
  return is_current_sha_focused and get_modification_type_from_new_sha(new_line, hunks, all_diff_output)
    or get_modification_type_from_old_sha(old_line, new_line, hunks, all_diff_output)
end

---Returns the matching line number of a line in the new/old version of the file compared to the current SHA.
---@param old_sha string
---@param new_sha string
---@param file_path string
---@param old_file_path string
---@param line_number number
---@return number|nil
M.calculate_matching_line_new = function(old_sha, new_sha, file_path, old_file_path, line_number)
  local net_change = 0
  local diff_cmd = string.format(
    "git diff --minimal --unified=0 --no-color %s %s -- %s %s",
    old_sha,
    new_sha,
    old_file_path,
    file_path
  )

  local handle = io.popen(diff_cmd)
  if handle == nil then
    u.notify(string.format("Error running git diff command for %s", file_path), vim.log.levels.ERROR)
    return nil
  end

  local all_lines = List.new({})
  for line in handle:lines() do
    table.insert(all_lines, line)
  end

  for i, line in ipairs(all_lines) do
    local hunk = M.parse_possible_hunk_headers(line)
    if hunk ~= nil then
      if line_number <= hunk.old_line then
        -- We have reached a hunk which starts after our target, return the changed total lines
        return line_number + net_change
      end

      local n = next_hunk_index(all_lines, i) or #all_lines
      local diff_lines = all_lines:slice(i + 1, n - 1)

      -- If the line is IN the hunk, process the hunk and return the change until that line
      if line_number >= hunk.old_line and line_number < hunk.old_line + hunk.old_range then
        net_change = line_number + net_change + net_changed_in_hunk_before_line(line_number, hunk, diff_lines)
        return net_change
      end

      -- If it's not it's after this hunk, just add all the changes and keep iterating
      net_change = net_change + count_changes(diff_lines)
    end
  end

  -- TODO: Possibly handle lines that are out of range in the new files
  return line_number + net_change + 1
end

return M
