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

func ReplyHandler(w http.ResponseWriter, r *http.Request, c HandlerClient, d *ProjectInfo) {
	w.Header().Set("Content-Type", "application/json")
	if r.Method != http.MethodPost {
		w.Header().Set("Access-Control-Allow-Methods", http.MethodPost)
		HandleError(w, InvalidRequestError{}, "Expected POST", http.StatusMethodNotAllowed)
		return
	}

	body, err := io.ReadAll(r.Body)
	if err != nil {
		HandleError(w, err, "Could not read request body", http.StatusBadRequest)
		return
	}

	defer r.Body.Close()
	var replyRequest ReplyRequest
	err = json.Unmarshal(body, &replyRequest)

	if err != nil {
		HandleError(w, err, "Could not read JSON from request", http.StatusBadRequest)
		return
	}

	now := time.Now()
	options := gitlab.AddMergeRequestDiscussionNoteOptions{
		Body:      gitlab.String(replyRequest.Reply),
		CreatedAt: &now,
	}

	note, res, err := c.AddMergeRequestDiscussionNote(d.ProjectId, d.MergeId, replyRequest.DiscussionId, &options)

	if err != nil {
		HandleError(w, err, "Could not leave reply", http.StatusInternalServerError)
		return
	}

	if res.StatusCode >= 300 {
		HandleError(w, GenericError{endpoint: "/reply"}, "Gitlab returned non-200 status", res.StatusCode)
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
		HandleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}
}
