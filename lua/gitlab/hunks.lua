local M = {}

---@class Hunk
---@field old_line integer
---@field old_range integer
---@field new_line integer
---@field new_range integer
---@field lines? string[] The hunk's body lines: context, added, and removed; prefixed with " ", "+", and "-", respectively.

---Parse a diff line into a Lua table if it's a hunk header, otherwise return nil.
---@param line string
---@return Hunk?
M.parse_possible_hunk_headers = function(line)
  if line:match("^@@") then
    -- match:
    --  @@ -23 +23 @@ ...
    --  @@ -23,0 +23 @@ ...
    --  @@ -41,0 +42,4 @@ ...
    local old_start, old_range, new_start, new_range = line:match("@@+ %-(%d+),?(%d*) %+(%d+),?(%d*) @@+")

    -- The unified diff format omits the ",N" count when it is exactly 1, so an empty
    -- capture means 1, while a captured "0" means a genuine zero-length range (pure
    -- insertion/deletion).
    return {
      old_line = tonumber(old_start),
      old_range = tonumber(old_range) or 1,
      new_line = tonumber(new_start),
      new_range = tonumber(new_range) or 1,
    }
  end
end

---Parse the diff between two commits for a file into a list of hunks.
---Each hunk carries its own header info and body lines.
---@param old_sha string SHA to diff from
---@param new_sha string SHA to diff to
---@param old_path string Old file name
---@param new_path string New file name
---@return Hunk[] hunks
M.get_hunks = function(old_sha, new_sha, old_path, new_path)
  local hunks = {}

  local git = require("gitlab.git")
  local diff, _ = git.diff_files(old_sha, new_sha, old_path, new_path)
  if diff == nil then
    return hunks
  end

  local current_hunk = nil
  for line in diff:gmatch("[^\r\n]+") do
    local hunk = M.parse_possible_hunk_headers(line)
    if hunk ~= nil then
      hunk.lines = {}
      table.insert(hunks, hunk)
      current_hunk = hunk
    elseif current_hunk ~= nil then
      local prefix = line:sub(1, 1)
      if prefix == " " or prefix == "+" or prefix == "-" then
        table.insert(current_hunk.lines, line)
      end
    end
  end

  return hunks
end

---Return the line position (old_line, new_line, type) for a queried line number.
---Walk the hunk list once. Callers use this for both the start and end of a line range.
---@param hunks Hunk[]
---@param linenr integer Line number on the focused side
---@param new_file_focused boolean Whether linenr is a line number in the new version of the file
---@return PositionInfo
M.get_line_position = function(hunks, linenr, new_file_focused)
  local net_change_before = 0

  for _, hunk in ipairs(hunks) do
    local hunk_start = new_file_focused and hunk.new_line or hunk.old_line
    local hunk_end = new_file_focused and (hunk.new_line + hunk.new_range - 1) or (hunk.old_line + hunk.old_range - 1)

    -- Inside the hunk
    if linenr >= hunk_start and linenr <= hunk_end then
      local old_cursor, new_cursor = hunk.old_line, hunk.new_line
      for _, line in ipairs(hunk.lines) do
        local prefix = line:sub(1, 1)
        if prefix == " " then
          if (new_file_focused and new_cursor == linenr) or (not new_file_focused and old_cursor == linenr) then
            return { old_line = old_cursor, new_line = new_cursor, type = "" }
          end
          old_cursor, new_cursor = old_cursor + 1, new_cursor + 1
        elseif prefix == "-" then
          if not new_file_focused and old_cursor == linenr then
            return { old_line = old_cursor, new_line = new_cursor, type = "old" }
          end
          old_cursor = old_cursor + 1
        elseif prefix == "+" then
          if new_file_focused and new_cursor == linenr then
            return { old_line = old_cursor, new_line = new_cursor, type = "new" }
          end
          new_cursor = new_cursor + 1
        end
      end
    -- Past the hunk
    elseif linenr > hunk_end then
      net_change_before = net_change_before + (hunk.new_range - hunk.old_range)
    end
  end

  -- When linenr falls outside every hunk (including each hunk's 3-line context, since
  -- M.get_hunks fetches the diff with --unified=3) the cursor was in unmodified content
  -- that Gitlab collapses - the type is "expanded".
  if new_file_focused then
    return { old_line = linenr - net_change_before, new_line = linenr, type = "expanded" }
  end
  return { old_line = linenr, new_line = linenr + net_change_before, type = "expanded" }
end

return M
