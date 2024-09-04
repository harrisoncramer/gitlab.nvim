package app

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"

	"github.com/xanzy/go-gitlab"
)

type DiscussionResolveRequest struct {
	DiscussionID string `json:"discussion_id"`
	Resolved     bool   `json:"resolved"`
}

/* discussionsResolveHandler sets a discussion to be "resolved" or not resolved, depending on the payload */
func (a *Api) discussionsResolveHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	if r.Method != http.MethodPut {
		w.Header().Set("Access-Control-Allow-Methods", http.MethodPut)
		handleError(w, InvalidRequestError{}, "Expected PUT", http.StatusMethodNotAllowed)
		return
	}

	body, err := io.ReadAll(r.Body)
	if err != nil {
		handleError(w, err, "Could not read request body", http.StatusBadRequest)
		return
	}

	defer r.Body.Close()

	var resolveDiscussionRequest DiscussionResolveRequest
	err = json.Unmarshal(body, &resolveDiscussionRequest)

	if err != nil {
		handleError(w, err, "Could not read JSON from request", http.StatusBadRequest)
		return
	}

	_, res, err := a.client.ResolveMergeRequestDiscussion(
		a.projectInfo.ProjectId,
		a.projectInfo.MergeId,
		resolveDiscussionRequest.DiscussionID,
		&gitlab.ResolveMergeRequestDiscussionOptions{Resolved: &resolveDiscussionRequest.Resolved},
	)

	friendlyName := "unresolve"
	if resolveDiscussionRequest.Resolved {
		friendlyName = "resolve"
	}

	if err != nil {
		handleError(w, err, fmt.Sprintf("Could not %s discussion", friendlyName), http.StatusInternalServerError)
		return
	}

	if res.StatusCode >= 300 {
		handleError(w, GenericError{endpoint: "/mr/discussions/resolve"}, fmt.Sprintf("Could not %s discussion", friendlyName), res.StatusCode)
		return
	}

	w.WriteHeader(http.StatusOK)
	response := SuccessResponse{
		Message: fmt.Sprintf("Discussion %sd", friendlyName),
		Status:  http.StatusOK,
	}

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		handleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}
}
