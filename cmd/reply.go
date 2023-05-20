package main

import (
	"encoding/json"
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
	if r.Method != http.MethodPost {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	c := r.Context().Value("client").(Client)

	body, err := io.ReadAll(r.Body)
	if err != nil {
		w.WriteHeader(http.StatusBadRequest)
		errMsg := map[string]string{"message": "Could not read request body"}
		jsonMsg, _ := json.Marshal(errMsg)
		w.Write(jsonMsg)
		return
	}

	defer r.Body.Close()
	var replyRequest ReplyRequest
	err = json.Unmarshal(body, &replyRequest)

	if err != nil {
		w.WriteHeader(http.StatusBadRequest)
		errMsg := map[string]string{"message": "Could not read JSON from request"}
		jsonMsg, _ := json.Marshal(errMsg)
		w.Write(jsonMsg)
		return
	}

	note, status, err := c.Reply(replyRequest)
	w.Header().Set("Content-Type", "application/json")

	if err != nil {
		response := ErrorResponse{
			Message: err.Error(),
			Status:  status,
		}
		json.NewEncoder(w).Encode(response)
		return
	}

	response := ReplyResponse{
		SuccessResponse: SuccessResponse{
			Message: fmt.Sprintf("Replied: %s", note.Body),
			Status:  http.StatusOK,
		},
		Note: note,
	}

	json.NewEncoder(w).Encode(response)
}
