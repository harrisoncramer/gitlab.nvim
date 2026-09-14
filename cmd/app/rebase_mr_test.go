package app

import (
	"net/http"
	"testing"

	gitlab "gitlab.com/gitlab-org/api/client-go"
)

type fakeMergeRequestRebaserClient struct {
	testBase
	rebaseInProgressCount int // number of times to return RebaseInProgress: true
	getMergeRequestCalls  int // tracks how many times GetMergeRequest was called
}

func (f *fakeMergeRequestRebaserClient) RebaseMergeRequest(pid interface{}, mergeRequest int64, opt *gitlab.RebaseMergeRequestOptions, options ...gitlab.RequestOptionFunc) (*gitlab.Response, error) {
	resp, err := f.handleGitlabError()
	if err != nil {
		return nil, err
	}

	return resp, err
}

func (f *fakeMergeRequestRebaserClient) GetMergeRequest(pid interface{}, mergeRequest int64, opt *gitlab.GetMergeRequestsOptions, options ...gitlab.RequestOptionFunc) (*gitlab.MergeRequest, *gitlab.Response, error) {
	resp, err := f.handleGitlabError()
	if err != nil {
		return nil, nil, err
	}

	f.getMergeRequestCalls++
	rebaseInProgress := f.getMergeRequestCalls <= f.rebaseInProgressCount

	return &gitlab.MergeRequest{RebaseInProgress: rebaseInProgress}, resp, err
}

func TestRebaseHandler(t *testing.T) {
	var testRebaseMrPayload = RebaseMrRequest{SkipCI: false}
	t.Run("Rebases merge request when rebase completes immediately", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/mr/rebase", testRebaseMrPayload)
		fakeClient := &fakeMergeRequestRebaserClient{rebaseInProgressCount: 0}
		svc := middleware(
			mergeRequestRebaserService{testProjectData, fakeClient},
			withMr(testProjectData, fakeMergeRequestLister{}),
			withPayloadValidation(methodToPayload{
				http.MethodPost: newPayload[RebaseMrRequest],
			}),
			withMethodCheck(http.MethodPost),
		)
		data := getSuccessData(t, svc, request)
		assert(t, data.Message, "MR rebased on server")
		assert(t, fakeClient.getMergeRequestCalls, 1)
	})
	t.Run("Rebases merge request and polls until rebase completes", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/mr/rebase", testRebaseMrPayload)
		fakeClient := &fakeMergeRequestRebaserClient{rebaseInProgressCount: 1}
		svc := middleware(
			mergeRequestRebaserService{testProjectData, fakeClient},
			withMr(testProjectData, fakeMergeRequestLister{}),
			withPayloadValidation(methodToPayload{
				http.MethodPost: newPayload[RebaseMrRequest],
			}),
			withMethodCheck(http.MethodPost),
		)
		data := getSuccessData(t, svc, request)
		assert(t, data.Message, "MR rebased on server")
		assert(t, fakeClient.getMergeRequestCalls, 2)
	})
	var testRebaseMrPayloadSkipCI = RebaseMrRequest{SkipCI: true}
	t.Run("Rebases merge request and skips CI", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/mr/rebase", testRebaseMrPayloadSkipCI)
		fakeClient := &fakeMergeRequestRebaserClient{}
		svc := middleware(
			mergeRequestRebaserService{testProjectData, fakeClient},
			withMr(testProjectData, fakeMergeRequestLister{}),
			withPayloadValidation(methodToPayload{
				http.MethodPost: newPayload[RebaseMrRequest],
			}),
			withMethodCheck(http.MethodPost),
		)
		data := getSuccessData(t, svc, request)
		assert(t, data.Message, "MR rebased on server (skipping CI)")
	})
	t.Run("Handles errors from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/mr/rebase", testRebaseMrPayload)
		svc := middleware(
			mergeRequestRebaserService{testProjectData, &fakeMergeRequestRebaserClient{testBase: testBase{errFromGitlab: true}}},
			withMr(testProjectData, fakeMergeRequestLister{}),
			withPayloadValidation(methodToPayload{
				http.MethodPost: newPayload[RebaseMrRequest],
			}),
			withMethodCheck(http.MethodPost),
		)
		data, _ := getFailData(t, svc, request)
		checkErrorFromGitlab(t, data, "Could not rebase MR")
	})
	t.Run("Handles non-200s from Gitlab", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/mr/rebase", testRebaseMrPayload)
		svc := middleware(
			mergeRequestRebaserService{testProjectData, &fakeMergeRequestRebaserClient{testBase: testBase{status: http.StatusSeeOther}}},
			withMr(testProjectData, fakeMergeRequestLister{}),
			withPayloadValidation(methodToPayload{
				http.MethodPost: newPayload[RebaseMrRequest],
			}),
			withMethodCheck(http.MethodPost),
		)
		data, _ := getFailData(t, svc, request)
		checkNon200(t, data, "Could not rebase MR", "/mr/rebase")
	})
}
