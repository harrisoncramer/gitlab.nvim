package main

import (
	"errors"
	"net/http"
	"testing"

	"github.com/xanzy/go-gitlab"
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
		request := makeRequest(t, http.MethodPost, "/approve", nil)
		server, _ := createRouterAndApi(fakeClient{approveMergeRequest: approveMergeRequest})
		data := serveRequest(t, server, request, SuccessResponse{})
		assert(t, data.Message, "Approved MR")
		assert(t, data.Status, http.StatusOK)
	})

	t.Run("Disallows non-POST method", func(t *testing.T) {
		request := makeRequest(t, http.MethodPut, "/approve", nil)
		server, _ := createRouterAndApi(fakeClient{approveMergeRequest: approveMergeRequest})
		data := serveRequest(t, server, request, ErrorResponse{})
		checkBadMethod(t, *data, http.MethodPost)
	})

	t.Run("Handles errors from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/approve", nil)
		server, _ := createRouterAndApi(fakeClient{approveMergeRequest: approveMergeRequestErr})
		data := serveRequest(t, server, request, ErrorResponse{})
		checkErrorFromGitlab(t, *data, "Could not approve merge request")
	})

	t.Run("Handles non-200s from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/approve", nil)
		server, _ := createRouterAndApi(fakeClient{approveMergeRequest: approveMergeRequestNon200})
		data := serveRequest(t, server, request, ErrorResponse{})
		checkNon200(t, *data, "Could not approve merge request", "/approve")
	})
}
