package main

import (
	"errors"
	"net/http"
	"testing"

	"github.com/xanzy/go-gitlab"
	mock_main "gitlab.com/harrisoncramer/gitlab.nvim/cmd/mocks"
)

func approveMergeRequest(pid interface{}, mr int, opt *gitlab.ApproveMergeRequestOptions, options ...gitlab.RequestOptionFunc) (*gitlab.MergeRequestApprovals, *gitlab.Response, error) {
	return &gitlab.MergeRequestApprovals{}, makeResponse(http.StatusOK), nil
}

func approveMergeRequestNon200(pid interface{}, mr int, opt *gitlab.ApproveMergeRequestOptions, options ...gitlab.RequestOptionFunc) (*gitlab.MergeRequestApprovals, *gitlab.Response, error) {
	return &gitlab.MergeRequestApprovals{}, makeResponse(http.StatusSeeOther), nil
}

func approveMergeRequestErr(pid interface{}, mr int, opt *gitlab.ApproveMergeRequestOptions, options ...gitlab.RequestOptionFunc) (*gitlab.MergeRequestApprovals, *gitlab.Response, error) {
	return &gitlab.MergeRequestApprovals{}, nil, errors.New("Some error from Gitlab")
}

func TestApproveHandler(t *testing.T) {
	t.Run("Approves merge request", func(t *testing.T) {
		mergeId := 3
		mockObj := mock_main.NewMockObj(t)

		options := gitlab.ListProjectMergeRequestsOptions{
			Scope:        gitlab.Ptr("all"),
			State:        gitlab.Ptr("opened"),
			SourceBranch: gitlab.Ptr(""),
		}

		mockObj.EXPECT().ApproveMergeRequest("", mergeId, nil, nil).Return(&gitlab.MergeRequestApprovals{}, makeResponse(http.StatusOK), nil)
		mockObj.EXPECT().ListProjectMergeRequests("", &options).Return([]*gitlab.MergeRequest{{IID: mergeId}}, makeResponse(http.StatusOK), nil)
		request := makeRequest(t, http.MethodPost, "/mr/approve", nil)
		server, _ := CreateRouterAndApi(mockObj)
		data := serveRequest(t, server, request, SuccessResponse{})

		assert(t, data.Message, "Approved MR")
		assert(t, data.Status, http.StatusOK)
	})

	t.Run("Disallows non-POST method", func(t *testing.T) {
		request := makeRequest(t, http.MethodPut, "/mr/approve", nil)
		server, _ := CreateRouterAndApi(fakeClient{approveMergeRequest: approveMergeRequest})
		data := serveRequest(t, server, request, ErrorResponse{})
		checkBadMethod(t, *data, http.MethodPost)
	})

	t.Run("Handles errors from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/mr/approve", nil)
		server, _ := CreateRouterAndApi(fakeClient{approveMergeRequest: approveMergeRequestErr})
		data := serveRequest(t, server, request, ErrorResponse{})
		checkErrorFromGitlab(t, *data, "Could not approve merge request")
	})

	t.Run("Handles non-200s from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/mr/approve", nil)
		server, _ := CreateRouterAndApi(fakeClient{approveMergeRequest: approveMergeRequestNon200})
		data := serveRequest(t, server, request, ErrorResponse{})
		checkNon200(t, *data, "Could not approve merge request", "/mr/approve")
	})
}
