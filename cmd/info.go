package main

import (
	"encoding/json"
	"errors"
	"net/http"

	"github.com/xanzy/go-gitlab"
)

type InfoResponse struct {
	SuccessResponse
	Info *gitlab.MergeRequest `json:"info"`
}

func InfoHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	c := r.Context().Value("client").(Client)

	if r.Method != http.MethodGet {
		w.Header().Set("Allow", http.MethodGet)
		c.handleError(w, errors.New("Invalid request type"), "That request type is not allowed", http.StatusMethodNotAllowed)
		return
	}

	mr, res, err := c.git.MergeRequests.GetMergeRequest(c.projectId, c.mergeId, &gitlab.GetMergeRequestsOptions{})
	if err != nil {
		c.handleError(w, err, "Could not get project info and initialize gitlab.nvim plugin", http.StatusBadRequest)
		return
	}

	if res.StatusCode >= 300 {
		c.handleError(w, err, "Gitlab returned non-200 status for info call", http.StatusBadRequest)
		return
	}

	w.WriteHeader(http.StatusOK)
	response := InfoResponse{
		SuccessResponse: SuccessResponse{
			Message: "Merge requests retrieved",
			Status:  http.StatusOK,
		},
		Info: mr,
	}

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		c.handleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}
}
