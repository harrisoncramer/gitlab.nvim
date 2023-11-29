package main

import (
	"bytes"
	"errors"
	"net/http"
	"testing"

	"github.com/xanzy/go-gitlab"
)

func getTraceFile(pid interface{}, jobID int, options ...gitlab.RequestOptionFunc) (*bytes.Reader, *gitlab.Response, error) {
	return bytes.NewReader([]byte("Some data")), makeResponse(http.StatusOK), nil
}

func getTraceFileErr(pid interface{}, jobID int, options ...gitlab.RequestOptionFunc) (*bytes.Reader, *gitlab.Response, error) {
	return nil, nil, errors.New("Some error from Gitlab")
}

func getTraceFileNon200(pid interface{}, jobID int, options ...gitlab.RequestOptionFunc) (*bytes.Reader, *gitlab.Response, error) {
	return nil, makeResponse(http.StatusSeeOther), nil
}

func TestJobHandler(t *testing.T) {
	t.Run("Should read a job trace file", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/job", JobTraceRequest{})
		server := createServer(fakeClient{getTraceFile: getTraceFile}, &ProjectInfo{}, MockAttachmentReader{})
		data := serveRequest(t, server, request, JobTraceResponse{})
		assert(t, data.SuccessResponse.Message, "Log file read")
		assert(t, data.SuccessResponse.Status, http.StatusOK)
		assert(t, data.File, "Some data")
	})

	t.Run("Disallows non-GET methods", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/job", JobTraceRequest{})
		server := createServer(fakeClient{getTraceFile: getTraceFile}, &ProjectInfo{}, MockAttachmentReader{})
		data := serveRequest(t, server, request, ErrorResponse{})
		checkBadMethod(t, *data, http.MethodGet)
	})

	t.Run("Should handle errors from Gitlab", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/job", JobTraceRequest{})
		server := createServer(fakeClient{getTraceFile: getTraceFileErr}, &ProjectInfo{}, MockAttachmentReader{})
		data := serveRequest(t, server, request, ErrorResponse{})
		checkErrorFromGitlab(t, *data, "Could not get trace file for job")
	})

	t.Run("Should handle non-200s", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/job", JobTraceRequest{})
		server := createServer(fakeClient{getTraceFile: getTraceFileNon200}, &ProjectInfo{}, MockAttachmentReader{})
		data := serveRequest(t, server, request, ErrorResponse{})
		checkNon200(t, *data, "Could not get trace file for job", "/job")
	})
}
