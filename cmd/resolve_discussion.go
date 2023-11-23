package main

import (
	"encoding/json"
	"errors"
	"io"
	"net/http"

	"github.com/xanzy/go-gitlab"
)

type DiscussionResolveRequest struct {
	DiscussionID string `json:"discussion_id"`
	Resolved     bool   `json:"resolved"`
}

func DiscussionResolveHandler(w http.ResponseWriter, r *http.Request, c HandlerClient, d *ProjectInfo) {
	w.Header().Set("Content-Type", "application/json")
	if r.Method != http.MethodPut {
		w.Header().Set("Allow", http.MethodPut)
		HandleError(w, errors.New("Invalid request type"), "That request type is not allowed", http.StatusMethodNotAllowed)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	body, err := io.ReadAll(r.Body)
	if err != nil {
		HandleError(w, err, "Could not read request body", http.StatusBadRequest)
		return
	}
	defer r.Body.Close()
	var resolveDiscussionRequest DiscussionResolveRequest
	err = json.Unmarshal(body, &resolveDiscussionRequest)
	if err != nil {
		HandleError(w, err, "Could not read JSON from request", http.StatusBadRequest)
		return
	}

	_, res, err := c.ResolveMergeRequestDiscussion(
		d.ProjectId,
		d.MergeId,
		resolveDiscussionRequest.DiscussionID,
		&gitlab.ResolveMergeRequestDiscussionOptions{Resolved: &resolveDiscussionRequest.Resolved},
	)

	if err != nil {
		HandleError(w, err, "Could not update resolve status of discussion", res.StatusCode)
		return
	}

	w.WriteHeader(http.StatusOK)
	var message string
	if resolveDiscussionRequest.Resolved {
		message = "Discussion resolved"
	} else {
		message = "Discussion unresolved"
	}
	response := SuccessResponse{
		Message: message,
		Status:  http.StatusOK,
	}

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		HandleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}
}
