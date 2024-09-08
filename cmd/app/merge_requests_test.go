package app

import (
	"net/http"
	"testing"

	"github.com/xanzy/go-gitlab"
)

type fakeMergeRequestLister struct {
	testBase
	emptyResponse bool
}

func (f fakeMergeRequestLister) ListProjectMergeRequests(pid interface{}, opt *gitlab.ListProjectMergeRequestsOptions, options ...gitlab.RequestOptionFunc) ([]*gitlab.MergeRequest, *gitlab.Response, error) {
	resp, err := f.handleGitlabError()
	if err != nil {
		return nil, nil, err
	}

	if f.emptyResponse {
		return []*gitlab.MergeRequest{}, resp, err
	}

	return []*gitlab.MergeRequest{{IID: 10}}, resp, err
}

func TestMergeRequestHandler(t *testing.T) {
	var testListMergeRequestsRequest = gitlab.ListProjectMergeRequestsOptions{}
	t.Run("Should fetch merge requests", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/merge_requests", testListMergeRequestsRequest)
		svc := mergeRequestListerService{testProjectData, fakeMergeRequestLister{}}
		data := getSuccessData(t, svc, request)
		assert(t, data.Status, http.StatusOK)
		assert(t, data.Message, "Merge requests fetched successfully")
	})
	t.Run("Handles error from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/merge_requests", testListMergeRequestsRequest)
		svc := mergeRequestListerService{testProjectData, fakeMergeRequestLister{testBase: testBase{errFromGitlab: true}}}
		data := getFailData(t, svc, request)
		checkErrorFromGitlab(t, data, "Failed to list merge requests")
		assert(t, data.Status, http.StatusInternalServerError)
	})
	t.Run("Handles non-200s from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/merge_requests", testListMergeRequestsRequest)
		svc := mergeRequestListerService{testProjectData, fakeMergeRequestLister{testBase: testBase{status: http.StatusSeeOther}}}
		data := getFailData(t, svc, request)
		checkNon200(t, data, "Failed to list merge requests", "/merge_requests")
		assert(t, data.Status, http.StatusSeeOther)
	})
	t.Run("Should handle not having any merge requests with 404", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/merge_requests", testListMergeRequestsRequest)
		svc := mergeRequestListerService{testProjectData, fakeMergeRequestLister{emptyResponse: true}}
		data := getFailData(t, svc, request)
		assert(t, data.Message, "No merge requests found")
		assert(t, data.Status, http.StatusNotFound)
	})
}
