package app

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"sync"

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

	return mrs, err
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

	type apiResponse struct {
		mrs []*gitlab.MergeRequest
		err error
	}

	mrChan := make(chan apiResponse, len(payloads))
	wg := sync.WaitGroup{}
	go func() {
		wg.Wait()
		close(mrChan)
	}()

	for _, payload := range payloads {
		wg.Add(1)
		go func(p gitlab.ListProjectMergeRequestsOptions) {
			defer wg.Done()
			mrs, err := a.callAPI(&p)
			mrChan <- apiResponse{mrs, err}
		}(payload)
	}

	var mergeRequests []*gitlab.MergeRequest
	var errs []error
	for res := range mrChan {
		if res.err != nil {
			errs = append(errs, res.err)
		} else {
			mergeRequests = append(mergeRequests, res.mrs...)
		}
	}

	if len(errs) > 0 {
		combinedErr := ""
		for _, err := range errs {
			combinedErr += err.Error() + "; "
		}
		handleError(w, errors.New(combinedErr), "Some error occurred", http.StatusInternalServerError)
		return
	}

	if len(mergeRequests) == 0 {
		handleError(w, errors.New(fmt.Sprintf("%s did not have any MRs", request.Username)), "No MRs found", http.StatusBadRequest)
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
