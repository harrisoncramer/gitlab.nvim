package main

import (
	"crypto/sha1"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"

	"github.com/xanzy/go-gitlab"
)

type PostCommentRequest struct {
	Comment        string     `json:"comment"`
	FileName       string     `json:"file_name"`
	NewLine        *int       `json:"new_line,omitempty"`
	OldLine        *int       `json:"old_line,omitempty"`
	HeadCommitSHA  string     `json:"head_commit_sha"`
	BaseCommitSHA  string     `json:"base_commit_sha"`
	StartCommitSHA string     `json:"start_commit_sha"`
	Type           string     `json:"type"`
	LineRange      *LineRange `json:"line_range,omitempty"`
}

// LineRange represents the range of a note.
type LineRange struct {
	StartRange *LinePosition `json:"start"`
	EndRange   *LinePosition `json:"end"`
}

// LinePosition represents a position in a line range.
// unlike gitlab struct this does not contain LineCode with sha1 of filename
type LinePosition struct {
	Type    string `json:"type"`
	OldLine int    `json:"old_line"`
	NewLine int    `json:"new_line"`
}

type DeleteCommentRequest struct {
	NoteId       int    `json:"note_id"`
	DiscussionId string `json:"discussion_id"`
}

type EditCommentRequest struct {
	Comment      string `json:"comment"`
	NoteId       int    `json:"note_id"`
	DiscussionId string `json:"discussion_id"`
	Resolved     bool   `json:"resolved"`
}

type CommentResponse struct {
	SuccessResponse
	Comment    *gitlab.Note       `json:"note"`
	Discussion *gitlab.Discussion `json:"discussion"`
}

func CommentHandler(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodDelete:
		DeleteComment(w, r)
	case http.MethodPost:
		PostComment(w, r)
	case http.MethodPatch:
		EditComment(w, r)
	default:
		w.WriteHeader(http.StatusMethodNotAllowed)
	}
}

func DeleteComment(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	c := r.Context().Value("client").(*gitlab.Client)
	d := r.Context().Value("data").(*ProjectInfo)

	body, err := io.ReadAll(r.Body)
	if err != nil {
		HandleError(w, err, "Could not read request body", http.StatusBadRequest)
		return
	}

	defer r.Body.Close()

	var deleteCommentRequest DeleteCommentRequest
	err = json.Unmarshal(body, &deleteCommentRequest)
	if err != nil {
		HandleError(w, err, "Could not read JSON from request", http.StatusBadRequest)
		return
	}

	res, err := c.Discussions.DeleteMergeRequestDiscussionNote(d.ProjectId, d.MergeId, deleteCommentRequest.DiscussionId, deleteCommentRequest.NoteId)

	if err != nil {
		HandleError(w, err, "Could not delete comment", res.StatusCode)
		return
	}

	/* TODO: Check status code */
	w.WriteHeader(http.StatusOK)
	response := SuccessResponse{
		Message: "Comment deleted succesfully",
		Status:  http.StatusOK,
	}

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		HandleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}
}

func PostComment(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	c := r.Context().Value("client").(*gitlab.Client)
	d := r.Context().Value("data").(*ProjectInfo)

	body, err := io.ReadAll(r.Body)
	if err != nil {
		HandleError(w, err, "Could not read request body", http.StatusBadRequest)
		return
	}

	defer r.Body.Close()

	var postCommentRequest PostCommentRequest
	err = json.Unmarshal(body, &postCommentRequest)
	if err != nil {
		HandleError(w, err, "Could not unmarshal data from request body", http.StatusBadRequest)
		return
	}

	opt := gitlab.CreateMergeRequestDiscussionOptions{
		Body: &postCommentRequest.Comment,
	}

	/* If we are leaving a comment on a line, leave position. Otherwise,
	we are leaving a note (unlinked comment) */
	if postCommentRequest.FileName != "" {
		opt.Position = &gitlab.PositionOptions{
			PositionType: &postCommentRequest.Type,
			StartSHA:     &postCommentRequest.StartCommitSHA,
			HeadSHA:      &postCommentRequest.HeadCommitSHA,
			BaseSHA:      &postCommentRequest.BaseCommitSHA,
			NewPath:      &postCommentRequest.FileName,
			OldPath:      &postCommentRequest.FileName,
			NewLine:      postCommentRequest.NewLine,
			OldLine:      postCommentRequest.OldLine,
		}

		if postCommentRequest.LineRange != nil {
			var format = "%x_%d_%d"
			var start_filename_sha1 = fmt.Sprintf(
				format,
				sha1.Sum([]byte(postCommentRequest.FileName)),
				postCommentRequest.LineRange.StartRange.OldLine,
				postCommentRequest.LineRange.StartRange.NewLine,
			)
			var end_filename_sha1 = fmt.Sprintf(
				format,
				sha1.Sum([]byte(postCommentRequest.FileName)),
				postCommentRequest.LineRange.EndRange.OldLine,
				postCommentRequest.LineRange.EndRange.NewLine,
			)
			opt.Position.LineRange = &gitlab.LineRangeOptions{
				Start: &gitlab.LinePositionOptions{
					Type:     &postCommentRequest.LineRange.StartRange.Type,
					LineCode: &start_filename_sha1,
				},
				End: &gitlab.LinePositionOptions{
					Type:     &postCommentRequest.LineRange.EndRange.Type,
					LineCode: &end_filename_sha1,
				},
			}
		}
	}

	discussion, _, err := c.Discussions.CreateMergeRequestDiscussion(d.ProjectId, d.MergeId, &opt)

	if err != nil {
		HandleError(w, err, "Could not create comment", http.StatusBadRequest)
		return
	}

	response := CommentResponse{
		SuccessResponse: SuccessResponse{
			Message: "Comment updated succesfully",
			Status:  http.StatusOK,
		},
		Comment:    discussion.Notes[0],
		Discussion: discussion,
	}

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		HandleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}
}

func EditComment(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	c := r.Context().Value("client").(*gitlab.Client)
	d := r.Context().Value("data").(*ProjectInfo)

	body, err := io.ReadAll(r.Body)
	if err != nil {
		HandleError(w, err, "Could not read request body", http.StatusBadRequest)
		return
	}

	defer r.Body.Close()

	var editCommentRequest EditCommentRequest
	err = json.Unmarshal(body, &editCommentRequest)
	if err != nil {
		HandleError(w, err, "Could not unmarshal data from request body", http.StatusBadRequest)
		return
	}

	options := gitlab.UpdateMergeRequestDiscussionNoteOptions{}

	msg := "edit comment"
	options.Body = gitlab.String(editCommentRequest.Comment)

	note, res, err := c.Discussions.UpdateMergeRequestDiscussionNote(d.ProjectId, d.MergeId, editCommentRequest.DiscussionId, editCommentRequest.NoteId, &options)

	if err != nil {
		HandleError(w, err, "Could not "+msg, res.StatusCode)
		return
	}

	w.WriteHeader(res.StatusCode)

	if res.StatusCode != http.StatusOK {
		HandleError(w, errors.New("Non-200 status code recieved"), "Could not "+msg, res.StatusCode)
	}

	response := CommentResponse{
		SuccessResponse: SuccessResponse{
			Message: "Comment updated succesfully",
			Status:  http.StatusOK,
		},
		Comment: note,
	}

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		HandleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}
}
