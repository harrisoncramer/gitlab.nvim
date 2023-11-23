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

type MrRequester interface {
	GetMergeRequest(pid interface{}, mergeRequest int, opt *gitlab.GetMergeRequestsOptions, options ...gitlab.RequestOptionFunc) (*gitlab.MergeRequest, *gitlab.Response, error)
}

func InfoHandler(w http.ResponseWriter, r *http.Request, c GitlabClient, d *ProjectInfo) {
	w.Header().Set("Content-Type", "application/json")
	if r.Method != http.MethodGet {
		w.Header().Set("Allow", http.MethodGet)
		HandleError(w, errors.New("Invalid request type"), "That request type is not allowed", http.StatusMethodNotAllowed)
		return
	}

	mr, res, err := c.GetMergeRequest(d.ProjectId, d.MergeId, &gitlab.GetMergeRequestsOptions{})
	if err != nil {
		HandleError(w, err, "Could not get project info and initialize gitlab.nvim plugin", http.StatusBadRequest)
		return
	}

	if res.StatusCode >= 300 {
		HandleError(w, err, "Gitlab returned non-200 status for info call", http.StatusBadRequest)
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
		HandleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}
}
