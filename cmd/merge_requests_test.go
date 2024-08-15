package main

import (
	"errors"
	"net/http"
	"testing"

	"github.com/xanzy/go-gitlab"
)

func listProjectMergeRequests200(pid interface{}, opt *gitlab.ListProjectMergeRequestsOptions, options ...gitlab.RequestOptionFunc) ([]*gitlab.MergeRequest, *gitlab.Response, error) {
	return []*gitlab.MergeRequest{{ID: 1}}, &gitlab.Response{}, nil
}

func listProjectMergeRequestsEmpty(pid interface{}, opt *gitlab.ListProjectMergeRequestsOptions, options ...gitlab.RequestOptionFunc) ([]*gitlab.MergeRequest, *gitlab.Response, error) {
	return []*gitlab.MergeRequest{}, &gitlab.Response{}, nil
}

func listProjectMergeRequestsErr(pid interface{}, opt *gitlab.ListProjectMergeRequestsOptions, options ...gitlab.RequestOptionFunc) ([]*gitlab.MergeRequest, *gitlab.Response, error) {
	return nil, nil, errors.New("Some error")
}

func TestMergeRequestHandler(t *testing.T) {
	t.Run("Should fetch merge requests", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/merge_requests", ListMergeRequestRequest{})
		server, _ := createRouterAndApi(fakeClient{listProjectMergeRequests: listProjectMergeRequests200})
		data := serveRequest(t, server, request, ListMergeRequestResponse{})
		assert(t, data.Message, "Merge requests fetched successfully")
		assert(t, data.Status, http.StatusOK)
	})
	t.Run("Should handle an error", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/merge_requests", ListMergeRequestRequest{})
		server, _ := createRouterAndApi(fakeClient{listProjectMergeRequests: listProjectMergeRequestsErr})
		data := serveRequest(t, server, request, ErrorResponse{})
		assert(t, data.Message, "Failed to list merge requests")
		assert(t, data.Status, http.StatusInternalServerError)
	})
	t.Run("Should handle not having any merge requests with 404", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/merge_requests", ListMergeRequestRequest{})
		server, _ := createRouterAndApi(fakeClient{listProjectMergeRequests: listProjectMergeRequestsEmpty})
		data := serveRequest(t, server, request, ErrorResponse{})
		assert(t, data.Message, "No merge requests found")
		assert(t, data.Status, http.StatusNotFound)
	})
}
