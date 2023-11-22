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
	w.Header().Set("Content-Type", "application/json")
	c := r.Context().Value("client").(*gitlab.Client)
	d := r.Context().Value("data").(*ProjectInfo)

	if r.Method != http.MethodGet {
		w.Header().Set("Allow", http.MethodGet)
		HandleError(w, errors.New("Invalid request type"), "That request type is not allowed", http.StatusMethodNotAllowed)
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}

	versionInfo, _, err := c.MergeRequests.GetMergeRequestDiffVersions(d.ProjectId, d.MergeId, &gitlab.GetMergeRequestDiffVersionsOptions{})
	if err != nil {
		HandleError(w, err, "Could not get diff version info", http.StatusBadRequest)
	}

	w.WriteHeader(http.StatusOK)
	response := RevisionsResponse{
		SuccessResponse: SuccessResponse{
			Message: "Revisions fetched successfully",
			Status:  http.StatusOK,
		},
		Revisions: versionInfo,
	}

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		HandleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}

}
