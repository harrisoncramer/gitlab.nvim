package main

import (
	"encoding/json"
	"io"
	"net/http"

	"github.com/xanzy/go-gitlab"
)

type AcceptMergeRequestRequest struct {
	Squash             bool   `json:"squash"`
	MergeMessage       string `json:"merge_message"`
	RemoveSourceBranch bool   `json:"remove_source_branch"`
}

/* mergeHandler merges a given merge request into the target branch */
func (a *api) mergeHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Access-Control-Allow-Methods", http.MethodGet)
	if r.Method != "POST" {
		handleError(w, InvalidRequestError{}, "Expected GET", http.StatusMethodNotAllowed)
		return
	}

	body, err := io.ReadAll(r.Body)
	if err != nil {
		handleError(w, err, "Could not read request body", http.StatusBadRequest)
		return
	}

	var acceptMergeRequest AcceptMergeRequestRequest
	err = json.Unmarshal(body, &acceptMergeRequest)
	if err != nil {
		handleError(w, err, "Could not unmarshal request body", http.StatusBadRequest)
		return
	}

	opts := gitlab.AcceptMergeRequestOptions{
		Squash:                   &acceptMergeRequest.Squash,
		ShouldRemoveSourceBranch: &acceptMergeRequest.RemoveSourceBranch,
		MergeCommitMessage:       &acceptMergeRequest.MergeMessage,
	}

	a.client.AcceptMergeRequest(a.projectInfo.ProjectId, a.projectInfo.MergeId, &opts)

}
