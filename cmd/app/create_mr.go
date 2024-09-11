package app

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"

	"github.com/xanzy/go-gitlab"
)

type CreateMrRequest struct {
	Title           string `json:"title"`
	Description     string `json:"description"`
	TargetBranch    string `json:"target_branch"`
	DeleteBranch    bool   `json:"delete_branch"`
	Squash          bool   `json:"squash"`
	TargetProjectID int    `json:"forked_project_id,omitempty"`
}

type MergeRequestCreator interface {
	CreateMergeRequest(pid interface{}, opt *gitlab.CreateMergeRequestOptions, options ...gitlab.RequestOptionFunc) (*gitlab.MergeRequest, *gitlab.Response, error)
}

type mergeRequestCreatorService struct {
	data
	client MergeRequestCreator
}

/* createMr creates a merge request */
func (a mergeRequestCreatorService) ServeHTTP(w http.ResponseWriter, r *http.Request) {
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

	if createMrRequest.Title == "" {
		handleError(w, errors.New("Title cannot be empty"), "Could not create MR", http.StatusBadRequest)
		return
	}

	if createMrRequest.TargetBranch == "" {
		handleError(w, errors.New("Target branch cannot be empty"), "Could not create MR", http.StatusBadRequest)
		return
	}

	opts := gitlab.CreateMergeRequestOptions{
		Title:              &createMrRequest.Title,
		Description:        &createMrRequest.Description,
		TargetBranch:       &createMrRequest.TargetBranch,
		SourceBranch:       &a.gitInfo.BranchName,
		RemoveSourceBranch: &createMrRequest.DeleteBranch,
		Squash:             &createMrRequest.Squash,
	}

	if createMrRequest.TargetProjectID != 0 {
		opts.TargetProjectID = gitlab.Ptr(createMrRequest.TargetProjectID)
	}

	_, res, err := a.client.CreateMergeRequest(a.projectInfo.ProjectId, &opts)

	if err != nil {
		handleError(w, err, "Could not create MR", http.StatusInternalServerError)
		return
	}

	if res.StatusCode >= 300 {
		handleError(w, GenericError{endpoint: "/create_mr"}, "Could not create MR", res.StatusCode)
		return
	}

	response := SuccessResponse{Message: fmt.Sprintf("MR '%s' created", createMrRequest.Title)}

	w.WriteHeader(http.StatusOK)

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		handleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}
}
