package app

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"

	"github.com/xanzy/go-gitlab"
)

func (a mergeRequestListerByUsernameService) callAPI(payload *gitlab.ListProjectMergeRequestsOptions) ([]*gitlab.MergeRequest, error) {
	mrs, res, err := a.client.ListProjectMergeRequests(a.projectInfo.ProjectId, payload)
	if err != nil {
		return []*gitlab.MergeRequest{}, err
	}

	if res.StatusCode >= 300 {
		return []*gitlab.MergeRequest{}, GenericError{endpoint: "/merge_requests"}
	}

	defer res.Body.Close()

	return mrs, nil
}

type MergeRequestListerByUsername interface {
	ListProjectMergeRequests(pid interface{}, opt *gitlab.ListProjectMergeRequestsOptions, options ...gitlab.RequestOptionFunc) ([]*gitlab.MergeRequest, *gitlab.Response, error)
}

type mergeRequestListerByUsernameService struct {
	data
	client MergeRequestListerByUsername
}

type MergeRequestByUsernameRequest struct {
	Username string  `json:"username"`
	State    *string `json:"state,omitempty"`
	Scope    *string `json:"scope,omitempty"`
}

func (a mergeRequestListerByUsernameService) handler(w http.ResponseWriter, r *http.Request) {
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
	var request MergeRequestByUsernameRequest
	err = json.Unmarshal(body, &request)
	if err != nil {
		handleError(w, err, "Could not read JSON from request", http.StatusBadRequest)
		return
	}

	// Assignee needs the ID of the assignee...
	payloads := []gitlab.ListProjectMergeRequestsOptions{
		{
			State:          request.State,
			Scope:          request.Scope,
			AuthorUsername: gitlab.Ptr(request.Username),
		},
		{
			State:            request.State,
			Scope:            request.Scope,
			ReviewerUsername: gitlab.Ptr(request.Username),
		},
	}

	mrChan := make(chan []*gitlab.MergeRequest, len(payloads))

	for _, payload := range payloads {
		go func(p gitlab.ListProjectMergeRequestsOptions) {
			mrs, err := a.callAPI(&p)
			if err != nil {
				fmt.Println("Oh no")
			}
			mrChan <- mrs
		}(payload)
	}

	var mergeRequests []*gitlab.MergeRequest
	for mrs := range mrChan {
		mergeRequests = append(mergeRequests, mrs...)
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
