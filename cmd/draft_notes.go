package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"

	"github.com/xanzy/go-gitlab"
)

/* The data coming from the client when creating a draft note is the same,
as when they are creating a normal comment, but the Gitlab
endpoints + resources we handle are different */

type PostDraftNoteRequest struct {
	Comment string `json:"comment"`
	PositionData
}

type DeleteDraftNoteRequest struct{}
type EditDraftNoteRequest struct{}

type DraftNoteResponse struct {
	SuccessResponse
	DraftNote *gitlab.DraftNote `json:"draft_note"`
}

/* DraftNoteWithPosition is a draft comment with an (optional) position data value embedded in it. The position data will be non-nil for range-based draft comments. */
type DraftNoteWithPosition struct {
	PositionData PositionData
}

func (draftNote DraftNoteWithPosition) GetPositionData() PositionData {
	return draftNote.PositionData
}

/* commentHandler creates, edits, and deletes draft discussions (comments, multi-line comments) */
func (a *api) draftNoteHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	switch r.Method {
	case http.MethodPost:
		a.postDraftNote(w, r)
	case http.MethodPatch:
		a.editDraftNote(w, r)
	case http.MethodDelete:
		a.deleteDraftNote(w, r)
	default:
		w.Header().Set("Access-Control-Allow-Methods", fmt.Sprintf("%s, %s, %s", http.MethodDelete, http.MethodPost, http.MethodPatch))
		handleError(w, InvalidRequestError{}, "Expected DELETE, POST or PATCH", http.StatusMethodNotAllowed)
	}
}

/* postComment creates a draft comment */
func (a *api) postDraftNote(w http.ResponseWriter, r *http.Request) {
	body, err := io.ReadAll(r.Body)
	if err != nil {
		handleError(w, err, "Could not read request body", http.StatusBadRequest)
		return
	}

	defer r.Body.Close()

	var postDraftNoteRequest PostDraftNoteRequest
	err = json.Unmarshal(body, &postDraftNoteRequest)
	if err != nil {
		handleError(w, err, "Could not unmarshal data from request body", http.StatusBadRequest)
		return
	}

	opt := gitlab.CreateDraftNoteOptions{
		Note: &postDraftNoteRequest.Comment,
		// InReplyToDiscussionID *string          `url:"in_reply_to_discussion_id,omitempty" json:"in_reply_to_discussion_id,omitempty"`
	}

	if postDraftNoteRequest.FileName != "" {
		draftNoteWithPosition := DraftNoteWithPosition{postDraftNoteRequest.PositionData}
		opt.Position = buildCommentPosition(draftNoteWithPosition)
	}

	draftNote, res, err := a.client.CreateDraftNote(a.projectInfo.ProjectId, a.projectInfo.MergeId, &opt)

	if err != nil {
		handleError(w, err, "Could not create draft note", http.StatusInternalServerError)
		return
	}

	if res.StatusCode >= 300 {
		handleError(w, GenericError{endpoint: "/mr/draft/comment"}, "Could not create draft note", res.StatusCode)
		return
	}

	w.WriteHeader(http.StatusOK)
	response := DraftNoteResponse{
		SuccessResponse: SuccessResponse{
			Message: "Draft note created successfully",
			Status:  http.StatusOK,
		},
		DraftNote: draftNote,
	}

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		handleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}

}

/* deleteComment deletes a draft comment */
func (a *api) deleteDraftNote(w http.ResponseWriter, r *http.Request) {}

/* deleteComment edits a draft comment */
func (a *api) editDraftNote(w http.ResponseWriter, r *http.Request) {}
