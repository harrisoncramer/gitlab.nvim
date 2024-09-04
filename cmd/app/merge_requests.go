package app

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"

	"github.com/xanzy/go-gitlab"
)

type ListMergeRequestRequest struct {
	Label    []string `json:"label"`
	NotLabel []string `json:"notlabel"`
}

type ListMergeRequestResponse struct {
	SuccessResponse
	MergeRequests []*gitlab.MergeRequest `json:"merge_requests"`
}

type MergeRequestLister interface {
	ListProjectMergeRequests(pid interface{}, opt *gitlab.ListProjectMergeRequestsOptions, options ...gitlab.RequestOptionFunc) ([]*gitlab.MergeRequest, *gitlab.Response, error)
}

type mergeRequestLister struct {
	client      MergeRequestLister
	projectInfo *ProjectInfo
}

func (a mergeRequestLister) mergeRequestsHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	if r.Method != http.MethodPost {
		w.Header().Set("Access-Control-Allow-Methods", http.MethodPost)
		handleError(w, InvalidRequestError{}, "Expected POST", http.StatusMethodNotAllowed)
		return
	}

	body, err := io.ReadAll(r.Body)
	if err != nil {
		handleError(w, err, "Could not read request body", http.StatusBadRequest)
		return
	}

	defer r.Body.Close()
	var listMergeRequestRequest ListMergeRequestRequest
	err = json.Unmarshal(body, &listMergeRequestRequest)
	if err != nil {
		handleError(w, err, "Could not read JSON from request", http.StatusBadRequest)
		return
	}

	options := gitlab.ListProjectMergeRequestsOptions{
		Scope:     gitlab.Ptr("all"),
		State:     gitlab.Ptr("opened"),
		Labels:    (*gitlab.LabelOptions)(&listMergeRequestRequest.Label),
		NotLabels: (*gitlab.LabelOptions)(&listMergeRequestRequest.NotLabel),
	}

	mergeRequests, res, err := a.client.ListProjectMergeRequests(a.projectInfo.ProjectId, &options)

	if err != nil {
		handleError(w, fmt.Errorf("Failed to list merge requests: %w", err), "Failed to list merge requests", http.StatusInternalServerError)
		return
	}

	if res.StatusCode >= 300 {
		handleError(w, GenericError{endpoint: "/merge_requests"}, "Failed to list merge requests", res.StatusCode)
		return
	}

	if len(mergeRequests) == 0 {
		handleError(w, errors.New("No merge requests found"), "No merge requests found", http.StatusNotFound)
		return
	}

	w.WriteHeader(http.StatusOK)
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
