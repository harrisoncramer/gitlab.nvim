-- A discussion or draft note anchored to a single commit has position line numbers
-- relative to that commit's isolated parent..commit diff, not the MR diff the regular
-- reviewer shows, so it must not be placed there. go-gitlab types commit_id as a plain
-- string, so a note without a commit arrives as "", never nil.

local common = require("gitlab.indicators.common")
local state = require("gitlab.state")

describe("indicators/common.filter_placeable_discussions", function()
  local original_discussion_data = state.DISCUSSION_DATA
  local original_draft_notes = state.DRAFT_NOTES

  after_each(function()
    state.DISCUSSION_DATA = original_discussion_data
    state.DRAFT_NOTES = original_draft_notes
  end)

  local function make_discussion(id, commit_id)
    return {
      id = id,
      notes = { { position = { new_line = 1 }, commit_id = commit_id } },
    }
  end

  local function make_draft_note(id, commit_id)
    return { id = id, position = { new_line = 1 }, commit_id = commit_id }
  end

  it("Filters out a discussion anchored to a commit (non-empty commit_id)", function()
    state.DISCUSSION_DATA = { discussions = { make_discussion("d1", "abc123") } }
    state.DRAFT_NOTES = {}

    local result = common.filter_placeable_discussions()

    assert.are.equal(0, #result)
  end)

  it("Keeps a discussion with commit_id as an empty string", function()
    state.DISCUSSION_DATA = { discussions = { make_discussion("d1", "") } }
    state.DRAFT_NOTES = {}

    local result = common.filter_placeable_discussions()

    assert.are.equal(1, #result)
  end)

  it("Keeps a discussion with commit_id as nil", function()
    state.DISCUSSION_DATA = { discussions = { make_discussion("d1", nil) } }
    state.DRAFT_NOTES = {}

    local result = common.filter_placeable_discussions()

    assert.are.equal(1, #result)
  end)

  it("Filters out a draft note anchored to a commit (non-empty commit_id)", function()
    state.DISCUSSION_DATA = { discussions = {} }
    state.DRAFT_NOTES = { make_draft_note("dn1", "abc123") }

    local result = common.filter_placeable_discussions()

    assert.are.equal(0, #result)
  end)

  it("Keeps a draft note with commit_id as an empty string", function()
    state.DISCUSSION_DATA = { discussions = {} }
    state.DRAFT_NOTES = { make_draft_note("dn1", "") }

    local result = common.filter_placeable_discussions()

    assert.are.equal(1, #result)
  end)
end)
