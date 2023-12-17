package main

import (
	"encoding/json"
	"net/http"
)

/* revokeHandler revokes approval for the current merge request */
func (a *api) revokeHandler(w http.ResponseWriter, r *http.Request) {
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
