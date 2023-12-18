package main

import (
	"encoding/json"
	"io"
	"net/http"

	"github.com/xanzy/go-gitlab"
)

type CreateMrRequest struct {
	Title        string `json:"title"`
	Description  string `json:"description"`
	SourceBranch string `json:"source_branch"`
	TargetBranch string `json:"target_branch"`
}

/* createMr creates a merge request */
func (a *api) createMr(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Access-Control-Allow-Methods", http.MethodGet)
	if r.Method != http.MethodPost {
		handleError(w, InvalidRequestError{}, "Expected POST", http.StatusMethodNotAllowed)
		return
	}

	body, err := io.ReadAll(r.Body)
	if err != nil {
		handleError(w, err, "Could not read request body", http.StatusBadRequest)
		return
	}

	var createMrRequest CreateMrRequest
	err = json.Unmarshal(body, &createMrRequest)
	if err != nil {
		handleError(w, err, "Could not unmarshal request body", http.StatusBadRequest)
		return
	}

	opts := gitlab.CreateMergeRequestOptions{
		Title:        &createMrRequest.Title,
		Description:  &createMrRequest.Description,
		TargetBranch: &createMrRequest.TargetBranch,
		SourceBranch: &a.gitInfo.BranchName,
	}

	_, res, err := a.client.CreateMergeRequest(a.projectInfo.ProjectId, &opts)

	if err != nil {
		handleError(w, err, "Could not merge MR", http.StatusInternalServerError)
		return
	}

	if res.StatusCode >= 300 {
		handleError(w, GenericError{endpoint: "/create_mr"}, "Could not create MR", res.StatusCode)
		return
	}

	response := SuccessResponse{
		Status:  http.StatusOK,
		Message: "MR created successfully",
	}

	w.WriteHeader(http.StatusOK)

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		handleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}
}
