package app

import (
	"net/http"
	"testing"

	"github.com/xanzy/go-gitlab"
)

type fakeMergeRequestListerByUsername struct {
	testBase
}

func (f fakeMergeRequestListerByUsername) ListProjectMergeRequests(pid interface{}, opt *gitlab.ListProjectMergeRequestsOptions, options ...gitlab.RequestOptionFunc) ([]*gitlab.MergeRequest, *gitlab.Response, error) {
	resp, err := f.handleGitlabError()
	if err != nil {
		return nil, nil, err
	}

	return []*gitlab.MergeRequest{{IID: 10}}, resp, err
}

func TestListMergeRequestByUsername(t *testing.T) {
	var testListMrsByUsernamePayload = MergeRequestByUsernameRequest{Username: "hcramer", UserId: 1234, State: "opened"}
	t.Run("Gets merge requests by username", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/merge_requests_by_username", testListMrsByUsernamePayload)
		svc := mergeRequestListerByUsernameService{testProjectData, fakeMergeRequestListerByUsername{}}
		data := getSuccessData(t, svc, request)
		assert(t, data.Message, "Merge requests fetched for hcramer")
		assert(t, data.Status, http.StatusOK)
	})
}
