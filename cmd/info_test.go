package main

import (
	"errors"
	"net/http"
	"testing"

	"github.com/xanzy/go-gitlab"
)

func getInfo(pid interface{}, mergeRequest int, opt *gitlab.GetMergeRequestsOptions, options ...gitlab.RequestOptionFunc) (*gitlab.MergeRequest, *gitlab.Response, error) {
	return &gitlab.MergeRequest{Title: "Some Title"}, makeResponse(200), nil
}

func getInfoNon200(pid interface{}, mergeRequest int, opt *gitlab.GetMergeRequestsOptions, options ...gitlab.RequestOptionFunc) (*gitlab.MergeRequest, *gitlab.Response, error) {
	return nil, makeResponse(http.StatusSeeOther), nil
}

func getInfoErr(pid interface{}, mergeRequest int, opt *gitlab.GetMergeRequestsOptions, options ...gitlab.RequestOptionFunc) (*gitlab.MergeRequest, *gitlab.Response, error) {
	return nil, nil, errors.New("Some error from Gitlab")
}

func TestInfoHandler(t *testing.T) {
	t.Run("Returns normal information", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/info", nil)
		server := createServer(fakeClient{getMergeRequestFn: getInfo}, &ProjectInfo{})
		data, err := serveRequest(server, request, InfoResponse{})
		if err != nil {
			t.Fatalf("Failed to read JSON: %v", err)
		}

		assert(t, data.Info.Title, "Some Title")
		assert(t, data.SuccessResponse.Message, "Merge requests retrieved")
		assert(t, data.SuccessResponse.Status, http.StatusOK)
	})

	t.Run("Disallows non-GET method", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/info", nil)
		server := createServer(fakeClient{getMergeRequestFn: getInfo}, &ProjectInfo{})
		data, err := serveRequest(server, request, ErrorResponse{})
		if err != nil {
			t.Fatalf("Failed to read JSON: %v", err)
		}

		assert(t, data.Status, http.StatusMethodNotAllowed)
		assert(t, data.Details, "Invalid request type")
		assert(t, data.Message, "Expected GET")
	})

	t.Run("Handles errors from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/info", nil)
		server := createServer(fakeClient{getMergeRequestFn: getInfoErr}, &ProjectInfo{})
		data, err := serveRequest(server, request, ErrorResponse{})
		if err != nil {
			t.Fatalf("Failed to read JSON: %v", err)
		}
		assert(t, data.Status, http.StatusInternalServerError)
		assert(t, data.Message, "Could not get project info")
		assert(t, data.Details, "Some error from Gitlab")
	})

	t.Run("Handles non-200s from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/info", nil)
		server := createServer(fakeClient{getMergeRequestFn: getInfoNon200}, &ProjectInfo{})
		data, err := serveRequest(server, request, ErrorResponse{})
		if err != nil {
			t.Fatalf("Failed to read JSON: %v", err)
		}

		assert(t, data.Status, http.StatusSeeOther)
		assert(t, data.Message, "Could not get project info")
		assert(t, data.Details, "An error occurred on the /info endpoint")
	})
}
