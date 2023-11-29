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
		server := createServer(fakeClient{approveMergeRequest: approveMergeRequest}, &ProjectInfo{}, MockAttachmentReader{})
		data := serveRequest(t, server, request, SuccessResponse{})
		assert(t, data.Message, "Approved MR")
		assert(t, data.Status, http.StatusOK)
	})

	t.Run("Disallows non-POST method", func(t *testing.T) {
		request := makeRequest(t, http.MethodPut, "/approve", nil)
		server := createServer(fakeClient{approveMergeRequest: approveMergeRequest}, &ProjectInfo{}, MockAttachmentReader{})
		data := serveRequest(t, server, request, ErrorResponse{})
		assert(t, data.Status, http.StatusMethodNotAllowed)
		assert(t, data.Details, "Invalid request type")
		assert(t, data.Message, "Expected POST")
	})

	t.Run("Handles errors from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/approve", nil)
		server := createServer(fakeClient{approveMergeRequest: approveMergeRequestErr}, &ProjectInfo{}, MockAttachmentReader{})
		data := serveRequest(t, server, request, ErrorResponse{})
		assert(t, data.Status, http.StatusInternalServerError)
		assert(t, data.Details, "Some error from Gitlab")
		assert(t, data.Message, "Could not approve merge request")
	})

	t.Run("Handles non-200s from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/approve", nil)
		server := createServer(fakeClient{approveMergeRequest: approveMergeRequestNon200}, &ProjectInfo{}, MockAttachmentReader{})
		data := serveRequest(t, server, request, ErrorResponse{})
		assert(t, data.Status, http.StatusSeeOther)
		assert(t, data.Details, "An error occurred on the /approve endpoint")
		assert(t, data.Message, "Could not approve merge request")
	})
}
