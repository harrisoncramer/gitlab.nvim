package main

import (
	"crypto/sha1"
	"encoding/json"
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

/* LineRange represents the range of a note. */
type LineRange struct {
	StartRange *LinePosition `json:"start"`
	EndRange   *LinePosition `json:"end"`
}

/* LinePosition represents a position in a line range. Unlike the Gitlab struct, this does not contain LineCode with a sha1 of the filename */
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

/* commentHandler creates, edits, and deletes discussions (comments, multi-line comments) */
func (a *api) commentHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	switch r.Method {
	case http.MethodPost:
		a.postComment(w, r)
	case http.MethodPatch:
		a.editComment(w, r)
	case http.MethodDelete:
		a.deleteComment(w, r)
	default:
		w.Header().Set("Access-Control-Allow-Methods", fmt.Sprintf("%s, %s, %s", http.MethodDelete, http.MethodPost, http.MethodPatch))
		handleError(w, InvalidRequestError{}, "Expected DELETE, POST or PATCH", http.StatusMethodNotAllowed)
	}
}

/* deleteComment deletes a note, multiline comment, or comment, which are all considered discussion notes. */
func (a *api) deleteComment(w http.ResponseWriter, r *http.Request) {
	body, err := io.ReadAll(r.Body)
	if err != nil {
		handleError(w, err, "Could not read request body", http.StatusBadRequest)
		return
	}

	defer r.Body.Close()

	var deleteCommentRequest DeleteCommentRequest
	err = json.Unmarshal(body, &deleteCommentRequest)
	if err != nil {
		handleError(w, err, "Could not read JSON from request", http.StatusBadRequest)
		return
	}

	res, err := a.client.DeleteMergeRequestDiscussionNote(a.projectInfo.ProjectId, a.projectInfo.MergeId, deleteCommentRequest.DiscussionId, deleteCommentRequest.NoteId)

	if err != nil {
		handleError(w, err, "Could not delete comment", http.StatusInternalServerError)
		return
	}

	if res.StatusCode >= 300 {
		handleError(w, GenericError{endpoint: "/mr/comment"}, "Could not delete comment", res.StatusCode)
		return
	}

	w.WriteHeader(http.StatusOK)
	response := SuccessResponse{
		Message: "Comment deleted successfully",
		Status:  http.StatusOK,
	}

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		handleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}
}

/* postComment creates a note, multiline comment, or comment. */
func (a *api) postComment(w http.ResponseWriter, r *http.Request) {
	body, err := io.ReadAll(r.Body)
	if err != nil {
		handleError(w, err, "Could not read request body", http.StatusBadRequest)
		return
	}

	defer r.Body.Close()

	var postCommentRequest PostCommentRequest
	err = json.Unmarshal(body, &postCommentRequest)
	if err != nil {
		handleError(w, err, "Could not unmarshal data from request body", http.StatusBadRequest)
		return
	}

	opt := gitlab.CreateMergeRequestDiscussionOptions{
		Body: &postCommentRequest.Comment,
	}

	/* If we are leaving a comment on a line, leave position. Otherwise,
	we are leaving a note (unlinked comment) */
	var friendlyName = "Note"
	if postCommentRequest.FileName != "" {
		friendlyName = "Comment"
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
			friendlyName = "Multiline Comment"
			shaFormat := "%x_%d_%d"
			startFilenameSha := fmt.Sprintf(
				shaFormat,
				sha1.Sum([]byte(postCommentRequest.FileName)),
				postCommentRequest.LineRange.StartRange.OldLine,
				postCommentRequest.LineRange.StartRange.NewLine,
			)
			endFilenameSha := fmt.Sprintf(
				shaFormat,
				sha1.Sum([]byte(postCommentRequest.FileName)),
				postCommentRequest.LineRange.EndRange.OldLine,
				postCommentRequest.LineRange.EndRange.NewLine,
			)
			opt.Position.LineRange = &gitlab.LineRangeOptions{
				Start: &gitlab.LinePositionOptions{
					Type:     &postCommentRequest.LineRange.StartRange.Type,
					LineCode: &startFilenameSha,
				},
				End: &gitlab.LinePositionOptions{
					Type:     &postCommentRequest.LineRange.EndRange.Type,
					LineCode: &endFilenameSha,
				},
			}
		}
	}

	discussion, res, err := a.client.CreateMergeRequestDiscussion(a.projectInfo.ProjectId, a.projectInfo.MergeId, &opt)

	if err != nil {
		handleError(w, err, "Could not create discussion", http.StatusInternalServerError)
		return
	}

	if res.StatusCode >= 300 {
		handleError(w, GenericError{endpoint: "/mr/comment"}, "Could not create discussion", res.StatusCode)
		return
	}

	w.WriteHeader(http.StatusOK)
	response := CommentResponse{
		SuccessResponse: SuccessResponse{
			Message: fmt.Sprintf("%s created successfully", friendlyName),
			Status:  http.StatusOK,
		},
		Comment:    discussion.Notes[0],
		Discussion: discussion,
	}

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		handleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}
}

/* editComment changes the text of a comment or changes it's resolved status. */
func (a *api) editComment(w http.ResponseWriter, r *http.Request) {
	body, err := io.ReadAll(r.Body)

	if err != nil {
		handleError(w, err, "Could not read request body", http.StatusBadRequest)
		return
	}

	defer r.Body.Close()

	var editCommentRequest EditCommentRequest
	err = json.Unmarshal(body, &editCommentRequest)
	if err != nil {
		handleError(w, err, "Could not unmarshal data from request body", http.StatusBadRequest)
		return
	}

	options := gitlab.UpdateMergeRequestDiscussionNoteOptions{}
	options.Body = gitlab.Ptr(editCommentRequest.Comment)

	note, res, err := a.client.UpdateMergeRequestDiscussionNote(a.projectInfo.ProjectId, a.projectInfo.MergeId, editCommentRequest.DiscussionId, editCommentRequest.NoteId, &options)

	if err != nil {
		handleError(w, err, "Could not update comment", http.StatusInternalServerError)
		return
	}

	if res.StatusCode >= 300 {
		handleError(w, GenericError{endpoint: "/mr/comment"}, "Could not update comment", res.StatusCode)
		return
	}

	w.WriteHeader(http.StatusOK)
	response := CommentResponse{
		SuccessResponse: SuccessResponse{
			Message: "Comment updated successfully",
			Status:  http.StatusOK,
		},
		Comment: note,
	}

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		handleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}
}
