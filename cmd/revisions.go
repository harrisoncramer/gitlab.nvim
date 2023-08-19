package main

import (
	"encoding/json"
	"errors"
	"net/http"

	"github.com/xanzy/go-gitlab"
)

type RevisionsResponse struct {
	SuccessResponse
	Revisions []*gitlab.MergeRequestDiffVersion
}

func RevisionsHandler(w http.ResponseWriter, r *http.Request) {
	c := r.Context().Value("client").(Client)
	w.Header().Set("Content-Type", "application/json")

	if r.Method != http.MethodGet {
		c.handleError(w, errors.New("Invalid request type"), "That request type is not allowed", http.StatusMethodNotAllowed)
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}

	versionInfo, _, err := c.git.MergeRequests.GetMergeRequestDiffVersions(c.projectId, c.mergeId, &gitlab.GetMergeRequestDiffVersionsOptions{})
	if err != nil {
		c.handleError(w, err, "Could not get diff version info", http.StatusBadRequest)
	}

	w.WriteHeader(http.StatusOK)
	response := RevisionsResponse{
		SuccessResponse: SuccessResponse{
			Message: "Revisions fetched successfully",
			Status:  http.StatusOK,
		},
		Revisions: versionInfo,
	}

	json.NewEncoder(w).Encode(response)

}
