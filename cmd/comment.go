package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"

	"github.com/xanzy/go-gitlab"
)

type PostCommentRequest struct {
	Comment string `json:"comment"`
	PositionData
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

/* CommentWithPosition is a comment with an (optional) position data value embedded in it. The position data will be non-nil for range-based comments. */
type CommentWithPosition struct {
	PositionData PositionData
}

func (comment CommentWithPosition) GetPositionData() PositionData {
	return comment.PositionData
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

	if postCommentRequest.FileName != "" {
		commentWithPositionData := CommentWithPosition{postCommentRequest.PositionData}
		opt.Position = buildCommentPosition(commentWithPositionData)
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
			Message: "Comment created successfully",
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
