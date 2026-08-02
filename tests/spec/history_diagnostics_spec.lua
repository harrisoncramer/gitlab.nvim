-- A commit-anchored comment is positioned in that commit's own diff, so the reviewer does
-- not show it (see indicators/common.lua). The browser draws it on the commit's new side.

local diagnostics = require("gitlab.indicators.diagnostics")
local common = require("gitlab.indicators.common")
local history = require("gitlab.reviewer.history")
local reviewer = require("gitlab.reviewer")
local diffview_lib = require("diffview.lib")
local signs = require("gitlab.indicators.signs")
local state = require("gitlab.state")

---@param id string
---@param commit_id string
---@param new_line integer
---@param path string
local function make_discussion(id, commit_id, new_line, path)
  return {
    id = id,
    notes = {
      {
        id = 1,
        author = { username = "author" },
        body = "Commented while browsing",
        commit_id = commit_id,
        created_at = "2026-08-01T10:00:00.000Z",
        resolvable = true,
        resolved = false,
        position = { new_path = path, old_path = path, new_line = new_line },
      },
    },
  }
end

---A note on a deleted line: old side, no new_line.
---@param id string
---@param commit_id string
local function make_old_side_discussion(id, commit_id, old_line, path)
  local discussion = make_discussion(id, commit_id, nil, path)
  discussion.notes[1].position.old_line = old_line
  return discussion
end

---@return integer bufnr
local function make_buffer()
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "one", "two", "three", "four", "five" })
  return bufnr
end

---@param bufnr integer
---@return vim.Diagnostic[]
local function placed(bufnr)
  return vim.diagnostic.get(bufnr, { namespace = diagnostics.diagnostics_namespace })
end

describe("indicators/common.filter_commit_discussions", function()
  after_each(function()
    state.DISCUSSION_DATA = nil
    state.DRAFT_NOTES = nil
  end)

  it("Keeps only the notes anchored to the given commit", function()
    state.DISCUSSION_DATA = {
      discussions = { make_discussion("d1", "sha1", 2, "f.lua"), make_discussion("d2", "sha2", 3, "f.lua") },
    }
    state.DRAFT_NOTES = {}

    local result = common.filter_commit_discussions("sha1")

    assert.are.equal(1, #result)
    assert.are.equal("d1", result[1].id)
  end)

  it("Keeps a draft note anchored to the commit", function()
    state.DISCUSSION_DATA = { discussions = {} }
    state.DRAFT_NOTES = { { id = 7, commit_id = "sha1", position = { new_path = "f.lua", new_line = 2 } } }

    local result = common.filter_commit_discussions("sha1")

    assert.are.equal(1, #result)
    assert.are.equal(7, result[1].id)
  end)

  it("Leaves out the notes that belong to the changeset instead of a commit", function()
    state.DISCUSSION_DATA = { discussions = { make_discussion("d1", "", 2, "f.lua") } }
    state.DRAFT_NOTES = {}

    assert.are.equal(0, #common.filter_commit_discussions("sha1"))
  end)
end)

describe("indicators/diagnostics.place_commit_diagnostics", function()
  local bufnr

  before_each(function()
    bufnr = make_buffer()
    state.settings.discussion_signs.enabled = true
    signs.setup_signs()
  end)

  after_each(function()
    vim.diagnostic.reset(diagnostics.diagnostics_namespace)
    vim.api.nvim_buf_delete(bufnr, { force = true })
    state.DISCUSSION_DATA = nil
    state.DRAFT_NOTES = nil
  end)

  it("Marks the commented line of the browsed commit", function()
    state.DISCUSSION_DATA = { discussions = { make_discussion("d1", "sha1", 3, "f.lua") } }
    state.DRAFT_NOTES = {}

    diagnostics.place_commit_diagnostics(bufnr, "sha1", "f.lua")

    local result = placed(bufnr)
    assert.are.equal(1, #result)
    assert.are.equal(2, result[1].lnum)
    assert.are.equal("d1", result[1].user_data.discussion_id)
  end)

  it("Leaves out the comments of other commits", function()
    state.DISCUSSION_DATA = { discussions = { make_discussion("d1", "sha2", 3, "f.lua") } }
    state.DRAFT_NOTES = {}

    diagnostics.place_commit_diagnostics(bufnr, "sha1", "f.lua")

    assert.are.equal(0, #placed(bufnr))
  end)

  it("Leaves out the comments on another file of the same commit", function()
    state.DISCUSSION_DATA = { discussions = { make_discussion("d1", "sha1", 3, "other.lua") } }
    state.DRAFT_NOTES = {}

    diagnostics.place_commit_diagnostics(bufnr, "sha1", "f.lua")

    assert.are.equal(0, #placed(bufnr))
  end)

  it("Leaves out a comment on a line the commit deletes", function()
    -- Old-side lines are numbered against the MR base, not the parent the browser shows.
    state.DISCUSSION_DATA = { discussions = { make_old_side_discussion("d1", "sha1", 3, "f.lua") } }
    state.DRAFT_NOTES = {}

    diagnostics.place_commit_diagnostics(bufnr, "sha1", "f.lua")

    assert.are.equal(0, #placed(bufnr))
  end)

  it("Replaces what another commit left on the buffer", function()
    state.DISCUSSION_DATA = { discussions = { make_discussion("d1", "sha1", 3, "f.lua") } }
    state.DRAFT_NOTES = {}
    diagnostics.place_commit_diagnostics(bufnr, "sha1", "f.lua")

    diagnostics.place_commit_diagnostics(bufnr, "sha2", "f.lua")

    assert.are.equal(0, #placed(bufnr))
  end)
end)

describe("reviewer/history.refresh_diagnostics", function()
  local bufnr, original_get_current_view, original_history_tabid

  before_each(function()
    bufnr = make_buffer()
    original_get_current_view = diffview_lib.get_current_view
    original_history_tabid = reviewer.history_tabid
    state.settings.discussion_signs.enabled = true
    signs.setup_signs()
    state.DISCUSSION_DATA = { discussions = { make_discussion("d1", "sha1", 4, "f.lua") } }
    state.DRAFT_NOTES = {}
    diffview_lib.get_current_view = function()
      return {
        panel = { cur_item = { { commit = { hash = "sha1" } }, { path = "f.lua" } } },
        cur_layout = { b = { file = { bufnr = bufnr } } },
      }
    end
  end)

  after_each(function()
    diffview_lib.get_current_view = original_get_current_view
    reviewer.history_tabid = original_history_tabid
    vim.diagnostic.reset(diagnostics.diagnostics_namespace)
    vim.api.nvim_buf_delete(bufnr, { force = true })
    state.DISCUSSION_DATA = nil
    state.DRAFT_NOTES = nil
  end)

  it("Draws the shown commit's comments on the new side", function()
    reviewer.history_tabid = vim.api.nvim_get_current_tabpage()

    history.refresh_diagnostics()

    local result = placed(bufnr)
    assert.are.equal(1, #result)
    assert.are.equal(3, result[1].lnum)
  end)

  it("Does nothing outside the commit browser", function()
    reviewer.history_tabid = nil

    history.refresh_diagnostics()

    assert.are.equal(0, #placed(bufnr))
  end)
end)

describe("reviewer/history.set_keymaps", function()
  it("Registers the jump to the discussion tree", function()
    local bufnr = vim.api.nvim_create_buf(false, true)

    history.set_keymaps(bufnr)

    local lhs = {}
    for _, map in ipairs(vim.api.nvim_buf_get_keymap(bufnr, "n")) do
      lhs[map.lhs] = true
    end
    assert.is_true(lhs[state.settings.keymaps.reviewer.move_to_discussion_tree] == true)

    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)
end)
