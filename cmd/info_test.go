package main

import (
	"errors"
	"net/http"
	"testing"

	"github.com/xanzy/go-gitlab"
)

func getInfo(pid interface{}, mergeRequest int, opt *gitlab.GetMergeRequestsOptions, options ...gitlab.RequestOptionFunc) (*gitlab.MergeRequest, *gitlab.Response, error) {
	return &gitlab.MergeRequest{Title: "Some Title"}, makeResponse(http.StatusOK), nil
}

func getInfoNon200(pid interface{}, mergeRequest int, opt *gitlab.GetMergeRequestsOptions, options ...gitlab.RequestOptionFunc) (*gitlab.MergeRequest, *gitlab.Response, error) {
	return nil, makeResponse(http.StatusSeeOther), nil
}

func getInfoErr(pid interface{}, mergeRequest int, opt *gitlab.GetMergeRequestsOptions, options ...gitlab.RequestOptionFunc) (*gitlab.MergeRequest, *gitlab.Response, error) {
	return nil, nil, errors.New("Some error from Gitlab")
}

func TestInfoHandler(t *testing.T) {
	t.Run("Returns normal information", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/mr/info", nil)
		server, _ := createRouterAndApi(fakeClient{getMergeRequest: getInfo})
		data := serveRequest(t, server, request, InfoResponse{})
		assert(t, data.Info.Title, "Some Title")
		assert(t, data.SuccessResponse.Message, "Merge requests retrieved")
		assert(t, data.SuccessResponse.Status, http.StatusOK)
	})

	t.Run("Disallows non-GET method", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/mr/info", nil)
		server, _ := createRouterAndApi(fakeClient{getMergeRequest: getInfo})
		data := serveRequest(t, server, request, ErrorResponse{})
		checkBadMethod(t, *data, http.MethodGet)
	})

	t.Run("Handles errors from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/mr/info", nil)
		server, _ := createRouterAndApi(fakeClient{getMergeRequest: getInfoErr})
		data := serveRequest(t, server, request, ErrorResponse{})
		checkErrorFromGitlab(t, *data, "Could not get project info")
	})

	t.Run("Handles non-200s from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/mr/info", nil)
		server, _ := createRouterAndApi(fakeClient{getMergeRequest: getInfoNon200})
		data := serveRequest(t, server, request, ErrorResponse{})
		checkNon200(t, *data, "Could not get project info", "/mr/info")
	})
}
