-- This module draws the discussion tree's indentation as inline virtual text, including
-- on the continuation of lines that Neovim soft-wraps.
--
-- Drawing the indentation virtually has these benefits: Note bodies start in column 0
-- so they are copied without the tree's indentation. Treesitter can parse
-- column-sensitive markdown constructs (e.g., fenced code blocks) correctly. The cost
-- is that 'breakindent' can no longer align wrapped lines (see
-- https://github.com/neovim/neovim/issues/35341).
--
-- 'breakindent' is replaced by a second set of extmarks, one at each point where the
-- text is predicted to wrap. An inline extmark straddles a wrap: as much of its virtual
-- text as still fits pads out the current screen line, and the remainder is drawn at
-- the start of the next one. Giving such a mark `indent + <columns left on this screen
-- line>` spaces therefore fills the current line to its edge and re-indents the
-- continuation, without a single character entering the buffer. The technique is
-- borrowed from this PR to nvim-orgmode:
-- https://github.com/nvim-orgmode/orgmode/pull/1017

local state = require("gitlab.state")

local M = {}

local ns = vim.api.nvim_create_namespace("gitlab_discussion_tree_indent")

---A tuple of `text` and optional `highlight`.
---@alias VirtText {[1]: string, [2]: string?}

---Return the number of display columns one level of nesting takes up.
---This is the configured `indent_width`, but cannot be less than the width of the
---expanders which are drawn inside the node's own level.
---@return integer
local function level_width()
  local settings = state.settings.discussion_tree
  return math.max(
    settings.indent_width,
    vim.fn.strdisplaywidth(settings.expanders.expanded),
    vim.fn.strdisplaywidth(settings.expanders.collapsed)
  )
end

---Pad `text` with spaces to exactly `width` display columns.
---Returns `text` unchanged when it is already at least that wide.
---@param text string
---@param width integer
---@return string
local function pad(text, width)
  return text .. string.rep(" ", math.max(width - vim.fn.strdisplaywidth(text), 0))
end

---A block of `width` columns of plain padding.
---@param width integer
---@return VirtText
local function padding(width)
  return { string.rep(" ", width) }
end

---The guide block the replies carry at the level of the note that started the thread.
---`nil` when guides are turned off.
---@param width integer
---@param kind "vertical"|"branch"|"last"
---@return VirtText?
local function guide(width, kind)
  local guides = state.settings.discussion_tree.indent_guides
  if not guides or guides[kind] == nil or guides[kind] == "" then
    return nil
  end
  local fill = kind == "vertical" and " " or (guides.horizontal ~= "" and guides.horizontal or " ")
  local block = guides[kind]
  while vim.fn.strdisplaywidth(block) < width do
    block = block .. fill
  end
  return { block, "GitlabIndentGuide" }
end

---The virtual text that indents one line of a node, as a list of VirtText chunks.
---
---A node's text starts at `depth * level_width()`, and the indentation is that many columns
---made of `depth` blocks, one per level of nesting. The last block belongs to the node itself
---and holds its expander when it has children; the blocks before it are its ancestors', and
---carry a guide only for the note that started the discussion. Drawing the expander inside a
---block rather than in front of the text is what keeps a note's header aligned with the bodies
---and replies underneath it, whatever the expander icons are.
---@param node NuiTree.Node
---@param ancestors table[] One block per ancestor level, innermost last
---@param width integer The width of one level, from `level_width()`
---@param expander boolean Whether to draw the node's expander, i.e. whether this is the line its text starts on
---@return VirtText[]
local function indent_chunks(node, ancestors, width, expander)
  local blocks = {}
  for _, block in ipairs(ancestors) do
    table.insert(blocks, block.chunk or padding(width))
  end

  local expanders = state.settings.discussion_tree.expanders
  if node:has_children() and expander then
    local icon = node:is_expanded() and expanders.expanded or expanders.collapsed
    table.insert(blocks, { pad(icon, width), "GitlabExpander" })
  else
    table.insert(blocks, padding(width))
  end

  return blocks
end

---The same blocks, as they are drawn on the lines *below* the one a node's text starts on: its
---own wrapped lines and everything nested under it. Only the innermost block changes, from the
---branch that ties a reply to its discussion to the plain vertical that carries on past it.
---@param ancestors table[]
---@return table[]
local function below(ancestors)
  local result = vim.list_extend({}, ancestors)
  local innermost = result[#result]
  if innermost ~= nil and innermost.branch then
    result[#result] = { chunk = innermost.below }
  end
  return result
end

---Work out the block each child of `node` carries at `node`'s own level, and the block its
---descendants carry below it.
---
---Only a discussion's root note produces guides: a reply is tied to the note it answers, and
---nothing else is. Every other level pads, so a reply's body is not joined to the reply's own
---header.
---@param node NuiTree.Node
---@param children NuiTree.Node[]
---@param width integer
---@return table<string, table> keyed by child node id
local function child_blocks(node, children, width)
  local blocks = {}
  if not node.is_root then
    for _, child in ipairs(children) do
      blocks[child:get_id()] = {}
    end
    return blocks
  end

  local last_reply
  for _, child in ipairs(children) do
    if child.type == "note" then
      last_reply = child:get_id()
    end
  end

  local seen_last = false
  for _, child in ipairs(children) do
    local id = child:get_id()
    if child.type == "note" then
      local is_last = id == last_reply
      blocks[id] = {
        chunk = guide(width, is_last and "last" or "branch"),
        below = not is_last and guide(width, "vertical") or nil,
        branch = true,
      }
      seen_last = is_last
    else
      -- A body line of the note itself: the discussion continues below it whenever a reply
      -- follows, and there is nothing left to join to once the last one has been passed.
      blocks[id] = { chunk = (last_reply ~= nil and not seen_last) and guide(width, "vertical") or nil }
    end
  end
  return blocks
end

---Virtual text that indents a wrapped line by `width` columns, opening it with the configured
---`wrap_marker` symbol. Unlike Vim's 'showbreak', the symbol is drawn inside the indentation
---rather than in front of the text, so it costs no columns and the text stays aligned. It is
---dropped if it would not fit within the indentation.
---@param chunks string[][] The node's indentation, from `indent_chunks`
---@param width integer Total display columns the chunks take up
---@return string[][]
local function wrapped_indent(chunks, width)
  local wrap_marker = state.settings.discussion_tree.wrap_marker
  local symbol = vim.fn.strdisplaywidth(wrap_marker)
  if wrap_marker == "" or symbol > width then
    return chunks
  end
  -- Trim the marker's width off the end of the indentation and put the marker there, so that it
  -- costs no columns and the text it precedes stays where it would otherwise be.
  local marked = {}
  local remaining = width - symbol
  for _, chunk in ipairs(chunks) do
    local chunk_width = vim.fn.strdisplaywidth(chunk[1])
    if remaining >= chunk_width then
      table.insert(marked, chunk)
      remaining = remaining - chunk_width
    elseif remaining > 0 then
      table.insert(marked, { vim.fn.strcharpart(chunk[1], 0, remaining), chunk[2] })
      remaining = 0
    end
  end
  table.insert(marked, { wrap_marker, "GitlabWrapMarker" })
  return marked
end

---Split a line the way 'linebreak' does: into chunks that each end with the characters a line
---may be broken after. A chunk is therefore a word together with the punctuation or whitespace
---trailing it, which is what has to fit on a screen line for the word to stay on it.
---@param line string
---@param breakat table<string, boolean>
---@return {byte: integer, width: integer}[]
local function chunks(line, breakat)
  -- Every character in \'breakat\' is ASCII, and no byte of a multibyte character ever is, so
  -- this can scan bytes without splitting a character.
  local list = {}
  local pos = 1
  while pos <= #line do
    local start = pos
    while pos <= #line and not breakat[line:sub(pos, pos)] do
      pos = pos + 1
    end
    while pos <= #line and breakat[line:sub(pos, pos)] do
      pos = pos + 1
    end
    table.insert(list, { byte = start, width = vim.fn.strdisplaywidth(line:sub(start, pos - 1)) })
  end
  return list
end

---Find the points at which Neovim will soft-wrap `line`, filling screen lines with as many
---whole chunks as fit, exactly as \'linebreak\' does.
---
---Only the chunks that start a line are returned; the caller draws the indentation in front of
---each of them. A chunk too wide for a line of its own is left alone, since Neovim then has to
---break it mid-chunk, at a point no virtual text can usefully be attached to.
---@param line string
---@param width integer Display columns available to the text itself on the first screen line
---@param indent integer Display columns the tree indents the line by
---@param lead integer Display columns of the line\'s own leading whitespace, which a wrapped line is indented by on top of the tree\'s indentation and so cannot use for text
---@param wrap boolean Whether the 'wrap' option is on
---@return integer[] byte 0-based byte positions of the chunks that start a wrapped line
local function wrap_points(line, width, indent, lead, breakat, wrap)
  local points = {}
  if width < 1 or width - lead < 1 or not wrap then
    return points
  end

  -- How much room a screen line has depends on what is drawn in front of it: the first line and
  -- every line this function marks give up columns to the indentation, while a line it leaves
  -- alone -- one holding a chunk too wide to be indented and still fit -- has the window to
  -- itself.
  local hanging = width - lead
  local full = width + indent

  local column = 0
  local capacity = width

  for _, chunk in ipairs(chunks(line, breakat)) do
    if column > 0 and column + chunk.width > capacity then
      -- The chunk cannot finish this line, so Neovim moves it down whole. Indenting it is only
      -- worth doing when it still fits afterwards; otherwise it is left flush.
      if chunk.width <= hanging then
        table.insert(points, chunk.byte - 1)
        capacity = hanging
      else
        capacity = full
      end
      column = chunk.width
    else
      column = column + chunk.width
    end

    if column > capacity then
      -- Wider than the line it starts on, so Neovim has to break it mid-chunk. What it spills
      -- onto carries no indentation of ours, and so has the full width.
      column = (column - capacity) % full
      capacity = full
    end
  end

  return points
end

---Display columns the text of a window has to itself, or nil if the buffer is not on screen.
---@param winid integer
---@return integer
local function text_width(winid)
  local win = vim.fn.getwininfo(winid)[1]
  -- `textoff` covers the sign, number and fold columns, which the text cannot use.
  return win.width - win.textoff
end

---Draw the indentation of every visible node.
---Draws indentation on the node's first screen line and, if 'wrap' is set, on each line
---it wraps onto.
---Safe to call repeatedly; each call replaces the marks of the one before.
---@param tree? NuiTree
M.apply = function(tree)
  if tree == nil then
    return
  end
  local bufnr = tree.bufnr
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

  local winid = vim.fn.bufwinid(bufnr)

  local width = winid > -1 and text_width(winid) or nil
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local level = level_width()

  -- Only insert indentation when 'wrap' is set for the window. Default to true.
  local wrap = true
  if winid > -1 then
    wrap = vim.wo[winid].wrap
  end

  local breakat = {}
  local option = vim.o.breakat
  for i = 1, #option do
    breakat[option:sub(i, i)] = true
  end

  ---Draw `node`, then everything under it.
  ---The tree is walked in order rather than by id, because a node's indentation depends
  ---on where its ancestors sit among their own siblings.
  ---@param node NuiTree.Node
  ---@param ancestors table[] One block per ancestor level, innermost last
  local function draw(node, ancestors)
    local _, start_linenr, end_linenr = tree:get_node(node:get_id())
    local indent = node._depth * level

    local beneath = below(ancestors)
    if start_linenr and indent > 0 then
      local prefix = indent_chunks(node, ancestors, level, true)
      local continuation = indent_chunks(node, beneath, level, false)
      for linenr = start_linenr, end_linenr or start_linenr do
        vim.api.nvim_buf_set_extmark(bufnr, ns, linenr - 1, 0, {
          virt_text = linenr == start_linenr and prefix or continuation,
          virt_text_pos = "inline",
          right_gravity = false,
        })

        -- With 'linebreak' set, Neovim keeps inline virtual text together with the chunk it
        -- sits in front of. A mark on a chunk that starts a wrapped line therefore moves down
        -- with it and is drawn at the very start of that screen line, which is exactly where
        -- the indentation belongs.
        local line = lines[linenr]
        if width ~= nil and line ~= nil then
          -- Wrapped lines hang under the text they continue, so they are indented by the
          -- line's own leading whitespace as well, the way 'breakindent' would do it.
          local lead = vim.fn.strdisplaywidth(line:match("^%s*"))
          local hanging = vim.list_extend(vim.deepcopy(continuation), { padding(lead) })
          local virt_text = wrapped_indent(hanging, indent + lead)
          for _, byte in ipairs(wrap_points(line, width - indent, indent, lead, breakat, wrap)) do
            vim.api.nvim_buf_set_extmark(bufnr, ns, linenr - 1, byte, {
              virt_text = virt_text,
              virt_text_pos = "inline",
              right_gravity = false,
            })
          end
        end
      end
    end

    if not node:is_expanded() then
      return
    end
    local children = tree:get_nodes(node:get_id())
    local blocks = child_blocks(node, children, level)
    for _, child in ipairs(children) do
      local inherited = vim.list_extend({}, beneath)
      table.insert(inherited, blocks[child:get_id()] or {})
      draw(child, inherited)
    end
  end

  for _, node in ipairs(tree:get_nodes()) do
    draw(node, {})
  end
end

return M
