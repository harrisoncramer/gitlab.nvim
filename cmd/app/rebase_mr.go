package app

import (
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	gitlab "gitlab.com/gitlab-org/api/client-go"
)

type RebaseMrRequest struct {
	SkipCI bool `json:"skip_ci,omitempty"`
}

type MergeRequestRebaser interface {
	RebaseMergeRequest(pid interface{}, mergeRequest int64, opt *gitlab.RebaseMergeRequestOptions, options ...gitlab.RequestOptionFunc) (*gitlab.Response, error)
}

type MergeRequestRebaserClient interface {
	MergeRequestRebaser
	MergeRequestGetter
}

type mergeRequestRebaserService struct {
	data
	client MergeRequestRebaserClient
}

/* Rebases a merge request on the server */
func (a mergeRequestRebaserService) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	payload := r.Context().Value(payload("payload")).(*RebaseMrRequest)

	opts := gitlab.RebaseMergeRequestOptions{
		SkipCI: &payload.SkipCI,
	}

	res, err := a.client.RebaseMergeRequest(a.projectInfo.ProjectId, a.projectInfo.MergeId, &opts)
	if err != nil {
		handleError(w, err, "Could not rebase MR", http.StatusInternalServerError)
		return
	}

	if res.StatusCode >= 300 {
		handleError(w, GenericError{r.URL.Path}, "Could not rebase MR", res.StatusCode)
		return
	}

	// Poll until rebase completes (GitLab rebase is async)
	for {
		mr, _, getMrErr := a.client.GetMergeRequest(
			a.projectInfo.ProjectId,
			a.projectInfo.MergeId,
			&gitlab.GetMergeRequestsOptions{
				IncludeRebaseInProgress: gitlab.Ptr(true),
			},
		)
		if getMrErr != nil {
			handleError(w, getMrErr, "Could not check rebase status", http.StatusInternalServerError)
			return
		}
		if !mr.RebaseInProgress {
			break
		}
		time.Sleep(1 * time.Second)
	}

	skippingCI := ""
	if payload.SkipCI {
		skippingCI = " (skipping CI)"
	}
	response := SuccessResponse{Message: fmt.Sprintf("MR rebased on server%s", skippingCI)}

	w.WriteHeader(http.StatusOK)

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		handleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}
}
