package app

import (
	"encoding/json"
	"io"
	"net/http"

	"github.com/xanzy/go-gitlab"
)

type AcceptMergeRequestRequest struct {
	Squash        bool   `json:"squash"`
	SquashMessage string `json:"squash_message"`
	DeleteBranch  bool   `json:"delete_branch"`
}

type MergeRequestAccepter interface {
	AcceptMergeRequest(pid interface{}, mergeRequest int, opt *gitlab.AcceptMergeRequestOptions, options ...gitlab.RequestOptionFunc) (*gitlab.MergeRequest, *gitlab.Response, error)
}

type mergeRequestAccepterService struct {
	data
	client MergeRequestAccepter
}

/* acceptAndMergeHandler merges a given merge request into the target branch */
func (a mergeRequestAccepterService) handler(w http.ResponseWriter, r *http.Request) {
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

	var acceptAndMergeRequest AcceptMergeRequestRequest
	err = json.Unmarshal(body, &acceptAndMergeRequest)
	if err != nil {
		handleError(w, err, "Could not unmarshal request body", http.StatusBadRequest)
		return
	}

	opts := gitlab.AcceptMergeRequestOptions{
		Squash:                   &acceptAndMergeRequest.Squash,
		ShouldRemoveSourceBranch: &acceptAndMergeRequest.DeleteBranch,
	}

	if acceptAndMergeRequest.SquashMessage != "" {
		opts.SquashCommitMessage = &acceptAndMergeRequest.SquashMessage
	}

	_, res, err := a.client.AcceptMergeRequest(a.projectInfo.ProjectId, a.projectInfo.MergeId, &opts)

	if err != nil {
		handleError(w, err, "Could not merge MR", http.StatusInternalServerError)
		return
	}

	if res.StatusCode >= 300 {
		handleError(w, GenericError{endpoint: "/mr/merge"}, "Could not merge MR", res.StatusCode)
		return
	}

	response := SuccessResponse{
		Status:  http.StatusOK,
		Message: "MR merged successfully",
	}

	w.WriteHeader(http.StatusOK)

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		handleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}
}
