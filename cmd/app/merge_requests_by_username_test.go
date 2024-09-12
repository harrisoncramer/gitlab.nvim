package app

import (
	"net/http"
	"strings"
	"testing"

	"github.com/xanzy/go-gitlab"
)

type fakeMergeRequestListerByUsername struct {
	testBase
	emptyResponse bool
}

func (f fakeMergeRequestListerByUsername) ListProjectMergeRequests(pid interface{}, opt *gitlab.ListProjectMergeRequestsOptions, options ...gitlab.RequestOptionFunc) ([]*gitlab.MergeRequest, *gitlab.Response, error) {
	resp, err := f.handleGitlabError()
	if err != nil {
		return nil, nil, err
	}

	if f.emptyResponse {
		return []*gitlab.MergeRequest{}, resp, err
	}

	return []*gitlab.MergeRequest{{IID: 10}}, resp, err
}

func TestListMergeRequestByUsername(t *testing.T) {
	var testListMrsByUsernamePayload = MergeRequestByUsernameRequest{Username: "hcramer", UserId: 1234, State: "opened"}
	t.Run("Gets merge requests by username", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/merge_requests_by_username", testListMrsByUsernamePayload)
		svc := middleware(
			mergeRequestListerByUsernameService{testProjectData, fakeMergeRequestListerByUsername{}},
			withPayloadValidation(methodToPayload{http.MethodPost: &MergeRequestByUsernameRequest{}}),
			withMethodCheck(http.MethodPost),
			withLogging,
		)
		data := getSuccessData(t, svc, request)
		assert(t, data.Message, "Merge requests fetched for hcramer")
	})

	t.Run("Should handle no merge requests", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/merge_requests_by_username", testListMrsByUsernamePayload)
		svc := middleware(
			mergeRequestListerByUsernameService{testProjectData, fakeMergeRequestListerByUsername{emptyResponse: true}},
			withPayloadValidation(methodToPayload{http.MethodPost: &MergeRequestByUsernameRequest{}}),
			withMethodCheck(http.MethodPost),
			withLogging,
		)
		data := getFailData(t, svc, request)
		assert(t, data.Message, "No MRs found")
		assert(t, data.Details, "hcramer did not have any MRs")
		assert(t, data.Status, http.StatusNotFound)
	})

	t.Run("Should require username", func(t *testing.T) {
		missingUsernamePayload := testListMrsByUsernamePayload
		missingUsernamePayload.Username = ""
		request := makeRequest(t, http.MethodPost, "/merge_requests_by_username", missingUsernamePayload)
		svc := middleware(
			mergeRequestListerByUsernameService{testProjectData, fakeMergeRequestListerByUsername{}},
			withPayloadValidation(methodToPayload{http.MethodPost: &MergeRequestByUsernameRequest{}}),
			withMethodCheck(http.MethodPost),
			withLogging,
		)
		data := getFailData(t, svc, request)
		assert(t, data.Message, "username is required")
		assert(t, data.Details, "username is a required payload field")
		assert(t, data.Status, http.StatusBadRequest)
	})

	t.Run("Should require User ID for assignee call", func(t *testing.T) {
		missingUsernamePayload := testListMrsByUsernamePayload
		missingUsernamePayload.UserId = 0
		request := makeRequest(t, http.MethodPost, "/merge_requests_by_username", missingUsernamePayload)
		svc := middleware(
			mergeRequestListerByUsernameService{testProjectData, fakeMergeRequestListerByUsername{}},
			withPayloadValidation(methodToPayload{http.MethodPost: &MergeRequestByUsernameRequest{}}),
			withMethodCheck(http.MethodPost),
			withLogging,
		)
		data := getFailData(t, svc, request)
		assert(t, data.Message, "user_id is required")
		assert(t, data.Details, "user_id is a required payload field")
		assert(t, data.Status, http.StatusBadRequest)
	})

	t.Run("Should handle error from Gitlab", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/merge_requests_by_username", testListMrsByUsernamePayload)
		svc := middleware(
			mergeRequestListerByUsernameService{testProjectData, fakeMergeRequestListerByUsername{testBase: testBase{errFromGitlab: true}}},
			withPayloadValidation(methodToPayload{http.MethodPost: &MergeRequestByUsernameRequest{}}),
			withMethodCheck(http.MethodPost),
			withLogging,
		)
		data := getFailData(t, svc, request)
		assert(t, data.Message, "An error occurred")
		assert(t, data.Details, strings.Repeat("Some error from Gitlab; ", 3))
		assert(t, data.Status, http.StatusInternalServerError)
	})

	t.Run("Handles non-200 from Gitlab", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/merge_requests_by_username", testListMrsByUsernamePayload)
		svc := middleware(
			mergeRequestListerByUsernameService{testProjectData, fakeMergeRequestListerByUsername{testBase: testBase{status: http.StatusSeeOther}}},
			withPayloadValidation(methodToPayload{http.MethodPost: &MergeRequestByUsernameRequest{}}),
			withMethodCheck(http.MethodPost),
			withLogging,
		)
		data := getFailData(t, svc, request)
		assert(t, data.Message, "An error occurred")
		assert(t, data.Details, strings.Repeat("An error occurred on the /merge_requests_by_username endpoint; ", 3))
		assert(t, data.Status, http.StatusInternalServerError)
	})
}
