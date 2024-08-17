package main

import (
	"bytes"
	"errors"
	"net/http"
	"testing"

	mock_main "gitlab.com/harrisoncramer/gitlab.nvim/cmd/mocks"
)

func TestJobHandler(t *testing.T) {
	t.Run("Should read a job trace file", func(t *testing.T) {
		mockObj := mock_main.NewMockObj(t)
		mockObj.EXPECT().GetTraceFile("", 0, mock_main.NoOp{}).Return(bytes.NewReader([]byte("Some data")), makeResponse(http.StatusOK), nil)

		request := makeRequest(t, http.MethodGet, "/job", JobTraceRequest{})
		server, _ := CreateRouterAndApi(mockObj)
		data := serveRequest(t, server, request, JobTraceResponse{})

		assert(t, data.SuccessResponse.Message, "Log file read")
		assert(t, data.SuccessResponse.Status, http.StatusOK)
		assert(t, data.File, "Some data")
	})

	t.Run("Disallows non-GET methods", func(t *testing.T) {
		mockObj := mock_main.NewMockObj(t)
		mockObj.EXPECT().GetTraceFile("", 0, mock_main.NoOp{}).Return(bytes.NewReader([]byte("Some data")), makeResponse(http.StatusOK), nil)

		request := makeRequest(t, http.MethodPost, "/job", JobTraceRequest{})
		server, _ := CreateRouterAndApi(mockObj)
		data := serveRequest(t, server, request, ErrorResponse{})

		checkBadMethod(t, *data, http.MethodGet)
	})

	t.Run("Should handle errors from Gitlab", func(t *testing.T) {
		mockObj := mock_main.NewMockObj(t)
		mockObj.EXPECT().GetTraceFile("", 0, mock_main.NoOp{}).Return(nil, nil, errors.New("Some error from Gitlab"))

		request := makeRequest(t, http.MethodGet, "/job", JobTraceRequest{})
		server, _ := CreateRouterAndApi(mockObj)
		data := serveRequest(t, server, request, ErrorResponse{})

		checkErrorFromGitlab(t, *data, "Could not get trace file for job")
	})

	t.Run("Should handle non-200s", func(t *testing.T) {
		mockObj := mock_main.NewMockObj(t)
		mockObj.EXPECT().GetTraceFile("", 0, mock_main.NoOp{}).Return(nil, makeResponse(http.StatusSeeOther), nil)

		request := makeRequest(t, http.MethodGet, "/job", JobTraceRequest{})
		server, _ := CreateRouterAndApi(mockObj)
		data := serveRequest(t, server, request, ErrorResponse{})

		checkNon200(t, *data, "Could not get trace file for job", "/job")
	})
}
