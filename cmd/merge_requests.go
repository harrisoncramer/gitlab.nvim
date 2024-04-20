package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http"

	"github.com/xanzy/go-gitlab"
)

type ListMergeRequestResponse struct {
	SuccessResponse
	MergeRequests []*gitlab.MergeRequest `json:"merge_requests"`
}

func (a *api) mergeRequestsHandler(w http.ResponseWriter, r *http.Request) {

	if r.Method != http.MethodGet {
		w.Header().Set("Access-Control-Allow-Methods", http.MethodGet)
		handleError(w, InvalidRequestError{}, "Expected GET", http.StatusMethodNotAllowed)
		return
	}

	options := gitlab.ListProjectMergeRequestsOptions{
		Scope: gitlab.Ptr("all"),
		State: gitlab.Ptr("opened"),
	}

	mergeRequests, _, err := a.client.ListProjectMergeRequests(a.projectInfo.ProjectId, &options)
	if err != nil {
		handleError(w, fmt.Errorf("Failed to list merge requests: %w", err), "Failed to list merge requests", http.StatusInternalServerError)
		return
	}

	if len(mergeRequests) == 0 {
		handleError(w, errors.New("No merge requests found"), "No merge requests found", http.StatusBadRequest)
		return
	}

	w.WriteHeader(200)
	response := ListMergeRequestResponse{
		SuccessResponse: SuccessResponse{
			Message: "Merge requests fetched successfully",
			Status:  http.StatusOK,
		},
		MergeRequests: mergeRequests,
	}

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		handleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}

}
