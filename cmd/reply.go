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

func (c *Client) Reply(r ReplyRequest) (*gitlab.Note, error) {

	now := time.Now()
	options := gitlab.AddMergeRequestDiscussionNoteOptions{
		Body:      gitlab.String(r.Reply),
		CreatedAt: &now,
	}

	note, _, err := c.git.Discussions.AddMergeRequestDiscussionNote(c.projectId, c.mergeId, r.DiscussionId, &options)

	if err != nil {
		return nil, fmt.Errorf("Could not leave reply: %w", err)
	}

	return note, nil
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

	note, err := c.Reply(replyRequest)

	if err != nil {
		errResp := map[string]string{"message": err.Error()}
		response, _ := json.Marshal(errResp)
		w.WriteHeader(http.StatusInternalServerError)
		w.Write(response)
		return
	}

	w.WriteHeader(http.StatusOK)
	w.Write([]byte(fmt.Sprintf(`{"message": "Replied: %s"}`, note.Body)))

	// Flush any buffered data to the client
	if flusher, ok := w.(http.Flusher); ok {
		flusher.Flush()
	}
}
