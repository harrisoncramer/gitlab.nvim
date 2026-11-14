package app

import (
	"crypto/sha1"
	"fmt"

	gitlab "gitlab.com/gitlab-org/api/client-go"
)

/* PositionInfo represents one endpoint (start or end) of a line range, as sent by the Lua
* plugin. Unlike the Gitlab struct, it has no LineCode - Lua can't compute a sha1, so
* buildCommentPosition computes one below from OldLine and NewLine.
*
* OldLine and NewLine are always real, non-nil integers, even when Type is "old" or "new"
* and only one side actually has a line. On the side that doesn't, the value is a position
* marker, not a claim that a line exists there: it's wherever that side's cursor was
* sitting when the other side's line was found. LineCode is always built from this
* unzeroed pair; buildCommentPosition separately zeroes the inapplicable side before
* setting it on the request's LineRange.{Start,End}.{OldLine,NewLine} - see
* zeroInapplicableLine. */
type PositionInfo struct {
	Type    string `json:"type"`
	OldLine int64  `json:"old_line"`
	NewLine int64  `json:"new_line"`
}

/* LineRange represents the range of a note. */
type LineRange struct {
	Start *PositionInfo `json:"start" validate:"required"`
	End   *PositionInfo `json:"end" validate:"required"`
}

/* PositionData represents the position of a comment or note (relative to a file diff) */
type PositionData struct {
	FileName       string     `json:"file_name"`
	OldFileName    string     `json:"old_file_name"`
	NewLine        *int64     `json:"new_line,omitempty"`
	OldLine        *int64     `json:"old_line,omitempty"`
	HeadCommitSHA  string     `json:"head_commit_sha"`
	BaseCommitSHA  string     `json:"base_commit_sha"`
	StartCommitSHA string     `json:"start_commit_sha"`
	Type           string     `json:"type"`
	LineRange      *LineRange `json:"line_range" validate:"required_with=FileName"`
	CommitID       string     `json:"commit_id,omitempty"`
}

/* RequestWithPosition is an interface that abstracts the handling of position data for a comment or a draft comment */
type RequestWithPosition interface {
	GetPositionData() PositionData
}

/* buildCommentPosition takes a comment or draft comment request and builds the position data necessary for a location-based comment */
func buildCommentPosition(commentWithPositionData RequestWithPosition) *gitlab.PositionOptions {
	positionData := commentWithPositionData.GetPositionData()

	opt := &gitlab.PositionOptions{
		PositionType: &positionData.Type,
		StartSHA:     &positionData.StartCommitSHA,
		HeadSHA:      &positionData.HeadCommitSHA,
		BaseSHA:      &positionData.BaseCommitSHA,
		NewPath:      &positionData.FileName,
		OldPath:      &positionData.OldFileName,
		NewLine:      positionData.NewLine,
		OldLine:      positionData.OldLine,
	}

	shaFormat := "%x_%d_%d"
	startFilenameSha := fmt.Sprintf(
		shaFormat,
		sha1.Sum([]byte(positionData.FileName)),
		positionData.LineRange.Start.OldLine,
		positionData.LineRange.Start.NewLine,
	)
	endFilenameSha := fmt.Sprintf(
		shaFormat,
		sha1.Sum([]byte(positionData.FileName)),
		positionData.LineRange.End.OldLine,
		positionData.LineRange.End.NewLine,
	)

	startOldLine, startNewLine := zeroInapplicableLine(positionData.LineRange.Start)
	endOldLine, endNewLine := zeroInapplicableLine(positionData.LineRange.End)

	opt.LineRange = &gitlab.LineRangeOptions{
		Start: &gitlab.LinePositionOptions{
			Type:     &positionData.LineRange.Start.Type,
			LineCode: &startFilenameSha,
			OldLine:  &startOldLine,
			NewLine:  &startNewLine,
		},
		End: &gitlab.LinePositionOptions{
			Type:     &positionData.LineRange.End.Type,
			LineCode: &endFilenameSha,
			OldLine:  &endOldLine,
			NewLine:  &endNewLine,
		},
	}

	return opt
}

/* zeroInapplicableLine returns a line_range endpoint's OldLine/NewLine with the side
* that its Type doesn't apply to zeroed out: NewLine for a deleted ("old") line, OldLine
* for an added ("new") line. Both stay real for an unmodified ("") or "expanded" line.
* The unzeroed pair is still what the LineCode hash above is computed from - Gitlab
* expects LineCode to encode the real old/new correspondence even when the displayed
* OldLine or NewLine is zeroed. */
func zeroInapplicableLine(position *PositionInfo) (oldLine int64, newLine int64) {
	oldLine, newLine = position.OldLine, position.NewLine
	switch position.Type {
	case "old":
		newLine = 0
	case "new":
		oldLine = 0
	}
	return oldLine, newLine
}
