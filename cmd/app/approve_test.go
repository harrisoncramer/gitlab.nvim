package app

import (
	"net/http"
	"testing"

	"github.com/xanzy/go-gitlab"
)

type fakeApprover struct {
	errFromGitlab bool
	status        int
}

func (f fakeApprover) ApproveMergeRequest(pid interface{}, mr int, opt *gitlab.ApproveMergeRequestOptions, options ...gitlab.RequestOptionFunc) (*gitlab.MergeRequestApprovals, *gitlab.Response, error) {
	if f.errFromGitlab {
		return nil, nil, errorFromGitlab
	}
	if f.status == 0 {
		f.status = 200
	}
	return &gitlab.MergeRequestApprovals{}, makeResponse(f.status), nil
}

func TestApproveHandler(t *testing.T) {
	t.Run("Approves merge request", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/mr/approve", nil)
		client := fakeApprover{}
		svc := mergeRequestApproverService{emptyProjectData, client}
		data := getSuccessData(t, svc, request)
		assert(t, data.Message, "Approved MR")
		assert(t, data.Status, http.StatusOK)
	})

	t.Run("Disallows non-POST method", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/mr/approve", nil)
		client := fakeApprover{}
		svc := mergeRequestApproverService{emptyProjectData, client}
		data := getFailData(t, svc, request)
		checkBadMethod(t, data, http.MethodPost)
	})

	t.Run("Handles errors from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/mr/approve", nil)
		client := fakeApprover{errFromGitlab: true}
		svc := mergeRequestApproverService{emptyProjectData, client}
		data := getFailData(t, svc, request)
		checkErrorFromGitlab(t, data, "Could not approve merge request")
	})

	t.Run("Handles non-200s from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/mr/approve", nil)
		client := fakeApprover{status: http.StatusSeeOther}
		svc := mergeRequestApproverService{emptyProjectData, client}
		data := getFailData(t, svc, request)
		checkNon200(t, data, "Could not approve merge request", "/mr/approve")
	})
}
