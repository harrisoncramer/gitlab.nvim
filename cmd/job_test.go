package main

import (
	"bytes"
	"net/http"
	"testing"

	mock_main "gitlab.com/harrisoncramer/gitlab.nvim/cmd/mocks"
)

var jobId = 0

func TestJobHandler(t *testing.T) {
	t.Run("Should read a job trace file", func(t *testing.T) {
		client := mock_main.NewMockClient(t)
		client.EXPECT().GetTraceFile("", jobId).Return(bytes.NewReader([]byte("Some data")), makeResponse(http.StatusOK), nil)

		request := makeRequest(t, http.MethodGet, "/job", JobTraceRequest{})
		server, _ := CreateRouterAndApi(client)
		data := serveRequest(t, server, request, JobTraceResponse{})

		assert(t, data.SuccessResponse.Message, "Log file read")
		assert(t, data.SuccessResponse.Status, http.StatusOK)
		assert(t, data.File, "Some data")
	})

	t.Run("Disallows non-GET methods", func(t *testing.T) {
		client := mock_main.NewMockClient(t)
		client.EXPECT().GetTraceFile("", jobId).Return(bytes.NewReader([]byte("Some data")), makeResponse(http.StatusOK), nil)

		request := makeRequest(t, http.MethodPost, "/job", JobTraceRequest{})
		server, _ := CreateRouterAndApi(client)
		data := serveRequest(t, server, request, ErrorResponse{})

		checkBadMethod(t, *data, http.MethodGet)
	})

	t.Run("Should handle errors from Gitlab", func(t *testing.T) {
		client := mock_main.NewMockClient(t)
		client.EXPECT().GetTraceFile("", jobId).Return(nil, nil, errorFromGitlab)

		request := makeRequest(t, http.MethodGet, "/job", JobTraceRequest{})
		server, _ := CreateRouterAndApi(client)
		data := serveRequest(t, server, request, ErrorResponse{})

		checkErrorFromGitlab(t, *data, "Could not get trace file for job")
	})

	t.Run("Should handle non-2jobIdjobIds", func(t *testing.T) {
		client := mock_main.NewMockClient(t)
		client.EXPECT().GetTraceFile("", jobId).Return(nil, makeResponse(http.StatusSeeOther), nil)

		request := makeRequest(t, http.MethodGet, "/job", JobTraceRequest{})
		server, _ := CreateRouterAndApi(client)
		data := serveRequest(t, server, request, ErrorResponse{})

		checkNon200(t, *data, "Could not get trace file for job", "/job")
	})
}
