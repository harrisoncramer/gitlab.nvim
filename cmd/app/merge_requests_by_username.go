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

type MergeRequestListerByUsername interface {
	ListProjectMergeRequests(pid interface{}, opt *gitlab.ListProjectMergeRequestsOptions, options ...gitlab.RequestOptionFunc) ([]*gitlab.MergeRequest, *gitlab.Response, error)
}

type mergeRequestListerByUsernameService struct {
	data
	client MergeRequestListerByUsername
}

type MergeRequestByUsernameRequest struct {
	UserId   int    `json:"user_id"`
	Username string `json:"username"`
	State    string `json:"state,omitempty"`
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

	if request.Username == "" {
		handleError(w, errors.New("username is a required payload field"), "username is required", http.StatusBadRequest)
		return
	}

	if request.UserId == 0 {
		handleError(w, errors.New("user_id is a required payload field"), "user_id is required", http.StatusBadRequest)
		return
	}

	if request.State == "" {
		request.State = "opened"
	}

	payloads := []gitlab.ListProjectMergeRequestsOptions{
		{
			AuthorUsername: gitlab.Ptr(request.Username),
			State:          gitlab.Ptr(request.State),
			Scope:          gitlab.Ptr("all"),
		},
		{
			ReviewerUsername: gitlab.Ptr(request.Username),
			State:            gitlab.Ptr(request.State),
			Scope:            gitlab.Ptr("all"),
		},
		{
			AssigneeID: gitlab.AssigneeID(request.UserId),
			State:      gitlab.Ptr(request.State),
			Scope:      gitlab.Ptr("all"),
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
			mrs, err := a.getMrs(&p)
			mrChan <- apiResponse{mrs, err}
		}(payload)
	}

	var mergeRequests []*gitlab.MergeRequest
	existingIds := make(map[int]bool)
	var errs []error
	for res := range mrChan {
		if res.err != nil {
			errs = append(errs, res.err)
		} else {
			for _, mr := range res.mrs {
				if !existingIds[mr.ID] {
					mergeRequests = append(mergeRequests, mr)
					existingIds[mr.ID] = true
				}
			}
		}
	}

	if len(errs) > 0 {
		combinedErr := ""
		for _, err := range errs {
			combinedErr += err.Error() + "; "
		}
		handleError(w, errors.New(combinedErr), "An error occurred", http.StatusInternalServerError)
		return
	}

	if len(mergeRequests) == 0 {
		handleError(w, fmt.Errorf("%s did not have any MRs", request.Username), "No MRs found", http.StatusNotFound)
		return
	}

	w.WriteHeader(http.StatusOK)
	response := ListMergeRequestResponse{
		SuccessResponse: SuccessResponse{
			Message: fmt.Sprintf("Merge requests fetched for %s", request.Username),
			Status:  http.StatusOK,
		},
		MergeRequests: mergeRequests,
	}

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		handleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}
}

func (a mergeRequestListerByUsernameService) getMrs(payload *gitlab.ListProjectMergeRequestsOptions) ([]*gitlab.MergeRequest, error) {
	mrs, res, err := a.client.ListProjectMergeRequests(a.projectInfo.ProjectId, payload)
	if err != nil {
		return []*gitlab.MergeRequest{}, err
	}

	if res.StatusCode >= 300 {
		return []*gitlab.MergeRequest{}, GenericError{endpoint: "/merge_requests_by_username"}
	}

	defer res.Body.Close()

	return mrs, err
}
