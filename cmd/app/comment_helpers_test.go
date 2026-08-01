package app

import (
	"testing"
)

func TestBuildCommentPosition(t *testing.T) {
	makePositionData := func(startType string, startOld, startNew int64, endType string, endOld, endNew int64) PositionData {
		return PositionData{
			FileName:       "file.txt",
			HeadCommitSHA:  "head-sha",
			BaseCommitSHA:  "base-sha",
			StartCommitSHA: "start-sha",
			Type:           "text",
			LineRange: &LineRange{
				Start: &PositionInfo{Type: startType, OldLine: startOld, NewLine: startNew},
				End:   &PositionInfo{Type: endType, OldLine: endOld, NewLine: endNew},
			},
		}
	}

	t.Run("zeroes NewLine for a deleted (\"old\") line, keeping LineCode's real pair", func(t *testing.T) {
		positionData := makePositionData("", 4, 4, "old", 5, 5)
		opt := buildCommentPosition(CommentWithPosition{PositionData: positionData})

		assert(t, *opt.LineRange.End.OldLine, int64(5))
		assert(t, *opt.LineRange.End.NewLine, int64(0))
		assert(t, *opt.LineRange.End.LineCode, "5436437fa01a7d3e41d46741da54b451446774ca_5_5")
	})

	t.Run("zeroes OldLine for an added (\"new\") line, keeping LineCode's real pair", func(t *testing.T) {
		positionData := makePositionData("", 4, 4, "new", 5, 5)
		opt := buildCommentPosition(CommentWithPosition{PositionData: positionData})

		assert(t, *opt.LineRange.End.OldLine, int64(0))
		assert(t, *opt.LineRange.End.NewLine, int64(5))
		assert(t, *opt.LineRange.End.LineCode, "5436437fa01a7d3e41d46741da54b451446774ca_5_5")
	})

	t.Run("keeps both lines real for an unmodified (\"\") line", func(t *testing.T) {
		positionData := makePositionData("", 4, 4, "", 5, 6)
		opt := buildCommentPosition(CommentWithPosition{PositionData: positionData})

		assert(t, *opt.LineRange.End.OldLine, int64(5))
		assert(t, *opt.LineRange.End.NewLine, int64(6))
	})

	t.Run("keeps both lines real for an expanded line", func(t *testing.T) {
		positionData := makePositionData("", 4, 4, "expanded", 59, 61)
		opt := buildCommentPosition(CommentWithPosition{PositionData: positionData})

		assert(t, *opt.LineRange.End.OldLine, int64(59))
		assert(t, *opt.LineRange.End.NewLine, int64(61))
	})

	t.Run("zeroes the start and end independently", func(t *testing.T) {
		positionData := makePositionData("new", 0, 50, "", 60, 62)
		opt := buildCommentPosition(CommentWithPosition{PositionData: positionData})

		assert(t, *opt.LineRange.Start.OldLine, int64(0))
		assert(t, *opt.LineRange.Start.NewLine, int64(50))
		assert(t, *opt.LineRange.End.OldLine, int64(60))
		assert(t, *opt.LineRange.End.NewLine, int64(62))
	})
}
