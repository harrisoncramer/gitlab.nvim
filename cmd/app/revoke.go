package app

import (
	"encoding/json"
	"net/http"

	"github.com/xanzy/go-gitlab"
)

type MergeRequestRevoker interface {
	UnapproveMergeRequest(interface{}, int, ...gitlab.RequestOptionFunc) (*gitlab.Response, error)
}

type mergeRequestRevokerService struct {
	data
	client MergeRequestRevoker
}

/* revokeHandler revokes approval for the current merge request */
func (a mergeRequestRevokerService) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	if r.Method != http.MethodPost {
		w.Header().Set("Access-Control-Allow-Methods", http.MethodPost)
		handleError(w, InvalidRequestError{}, "Expected POST", http.StatusMethodNotAllowed)
		return
	}

	res, err := a.client.UnapproveMergeRequest(a.projectInfo.ProjectId, a.projectInfo.MergeId, nil, nil)

	if err != nil {
		handleError(w, err, "Could not revoke approval", http.StatusInternalServerError)
		return
	}

	if res.StatusCode >= 300 {
		handleError(w, GenericError{endpoint: "/mr/revoke"}, "Could not revoke approval", res.StatusCode)
		return
	}

	w.WriteHeader(http.StatusOK)
	response := SuccessResponse{
		Message: "Success! Revoked MR approval",
		Status:  http.StatusOK,
	}

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		handleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}
}
