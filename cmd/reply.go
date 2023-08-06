package main

import (
	"encoding/json"
	"errors"
	"fmt"
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

func (c *Client) Reply(r ReplyRequest) (*gitlab.Note, int, error) {

	now := time.Now()
	options := gitlab.AddMergeRequestDiscussionNoteOptions{
		Body:      gitlab.String(r.Reply),
		CreatedAt: &now,
	}

	note, res, err := c.git.Discussions.AddMergeRequestDiscussionNote(c.projectId, c.mergeId, r.DiscussionId, &options)

	if err != nil {
		return nil, res.Response.StatusCode, fmt.Errorf("Could not leave reply: %w", err)
	}

	return note, http.StatusOK, nil
}

func ReplyHandler(w http.ResponseWriter, r *http.Request) {
	c := r.Context().Value("client").(Client)
	w.Header().Set("Content-Type", "application/json")

	if r.Method != http.MethodPost {
		c.handleError(w, errors.New("Invalid request type"), "That request type is not allowed", http.StatusMethodNotAllowed)
		return
	}

	body, err := io.ReadAll(r.Body)
	if err != nil {
		c.handleError(w, err, "Could not read request body", http.StatusBadRequest)
		return
	}

	defer r.Body.Close()
	var replyRequest ReplyRequest
	err = json.Unmarshal(body, &replyRequest)

	if err != nil {
		c.handleError(w, err, "Could not read JSON from request", http.StatusBadRequest)
		return
	}

	note, status, err := c.Reply(replyRequest)

	if err != nil {
		c.handleError(w, err, "Could not send reply", status)
		return
	}

	w.WriteHeader(status)
	response := ReplyResponse{
		SuccessResponse: SuccessResponse{
			Message: fmt.Sprintf("Replied: %s", note.Body),
			Status:  http.StatusOK,
		},
		Note: note,
	}

	json.NewEncoder(w).Encode(response)
}
