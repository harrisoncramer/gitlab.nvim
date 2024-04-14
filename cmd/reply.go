package main

import (
	"encoding/json"
	"io"
	"net/http"
	"time"

	"github.com/xanzy/go-gitlab"
)

type ReplyRequest struct {
	DiscussionId string `json:"discussion_id"`
	Reply        string `json:"reply"`
}

type ReplyResponse struct {
	SuccessResponse
	Note *gitlab.Note `json:"note"`
}

/* replyHandler sends a reply to a note or comment */
func (a *api) replyHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	if r.Method != http.MethodPost {
		w.Header().Set("Access-Control-Allow-Methods", http.MethodPost)
		handleError(w, InvalidRequestError{}, "Expected POST", http.StatusMethodNotAllowed)
		return
	}

	body, err := io.ReadAll(r.Body)
	if err != nil {
		handleError(w, err, "Could not read request body", http.StatusBadRequest)
		return
	}

	defer r.Body.Close()
	var replyRequest ReplyRequest
	err = json.Unmarshal(body, &replyRequest)

	if err != nil {
		handleError(w, err, "Could not read JSON from request", http.StatusBadRequest)
		return
	}

	now := time.Now()
	options := gitlab.AddMergeRequestDiscussionNoteOptions{
		Body:      gitlab.Ptr(replyRequest.Reply),
		CreatedAt: &now,
	}

	note, res, err := a.client.AddMergeRequestDiscussionNote(a.projectInfo.ProjectId, a.projectInfo.MergeId, replyRequest.DiscussionId, &options)

	if err != nil {
		handleError(w, err, "Could not leave reply", http.StatusInternalServerError)
		return
	}

	if res.StatusCode >= 300 {
		handleError(w, GenericError{endpoint: "/mr/reply"}, "Could not leave reply", res.StatusCode)
		return
	}

	w.WriteHeader(http.StatusOK)
	response := ReplyResponse{
		SuccessResponse: SuccessResponse{
			Message: "Replied to comment",
			Status:  http.StatusOK,
		},
		Note: note,
	}

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		handleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}
}
