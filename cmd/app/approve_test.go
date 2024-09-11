package app

import (
	"net/http"
	"testing"

	"github.com/xanzy/go-gitlab"
)

type fakeApproverClient struct {
	testBase
}

func (f fakeApproverClient) ApproveMergeRequest(pid interface{}, mr int, opt *gitlab.ApproveMergeRequestOptions, options ...gitlab.RequestOptionFunc) (*gitlab.MergeRequestApprovals, *gitlab.Response, error) {
	resp, err := f.handleGitlabError()
	if err != nil {
		return nil, nil, err
	}
	return &gitlab.MergeRequestApprovals{}, resp, nil
}

func TestApproveHandler(t *testing.T) {
	t.Run("Approves merge request", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/mr/approve", nil)
		client := fakeApproverClient{}
		svc := middleware(
			withMr(mergeRequestApproverService{testProjectData, client}, testProjectData, fakeMergeRequestLister{}),
			validateMethods(http.MethodPost),
			logMiddleware,
		)
		data := getSuccessData(t, svc, request)
		assert(t, data.Message, "Approved MR")
		assert(t, data.Status, http.StatusOK)
	})

	t.Run("Disallows non-POST method", func(t *testing.T) {
		request := makeRequest(t, http.MethodPut, "/mr/approve", nil)
		client := fakeApproverClient{}
		svc := middleware(
			withMr(mergeRequestApproverService{testProjectData, client}, testProjectData, fakeMergeRequestLister{}),
			validateMethods(http.MethodPost),
			logMiddleware,
		)
		data := getFailData(t, svc, request)
		checkBadMethod(t, data, http.MethodPost)
	})

	t.Run("Handles errors from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/mr/approve", nil)
		client := fakeApproverClient{testBase{errFromGitlab: true}}
		svc := middleware(
			withMr(mergeRequestApproverService{testProjectData, client}, testProjectData, fakeMergeRequestLister{}),
			validateMethods(http.MethodPost),
			logMiddleware,
		)
		data := getFailData(t, svc, request)
		checkErrorFromGitlab(t, data, "Could not approve merge request")
	})

	t.Run("Handles non-200s from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/mr/approve", nil)
		client := fakeApproverClient{testBase{status: http.StatusSeeOther}}
		svc := middleware(
			withMr(mergeRequestApproverService{testProjectData, client}, testProjectData, fakeMergeRequestLister{}),
			validateMethods(http.MethodPost),
			logMiddleware,
		)
		data := getFailData(t, svc, request)
		checkNon200(t, data, "Could not approve merge request", "/mr/approve")
	})
}
