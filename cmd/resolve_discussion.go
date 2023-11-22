package main

import (
	"encoding/json"
	"io"
	"net/http"

	"github.com/xanzy/go-gitlab"
)

type DiscussionResolveRequest struct {
	DiscussionID string `json:"discussion_id"`
	Resolved     bool   `json:"resolved"`
}

func DiscussionResolveHandler(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodPut:
		DiscussionResolve(w, r)
	default:
		w.WriteHeader(http.StatusMethodNotAllowed)
	}
}
func DiscussionResolve(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	c := r.Context().Value("client").(*gitlab.Client)
	d := r.Context().Value("data").(*ProjectInfo)

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

	_, res, err := c.Discussions.ResolveMergeRequestDiscussion(
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
