package main

import (
	"errors"
	"net/http"
	"testing"

	"github.com/xanzy/go-gitlab"
)

func listPipelineJobs(pid interface{}, pipelineID int, opts *gitlab.ListJobsOptions, options ...gitlab.RequestOptionFunc) ([]*gitlab.Job, *gitlab.Response, error) {
	return []*gitlab.Job{}, makeResponse(http.StatusOK), nil
}

func listPipelineJobsErr(pid interface{}, pipelineID int, opts *gitlab.ListJobsOptions, options ...gitlab.RequestOptionFunc) ([]*gitlab.Job, *gitlab.Response, error) {
	return nil, nil, errors.New("Some error from Gitlab")
}

func listPipelineJobsNon200(pid interface{}, pipelineID int, opts *gitlab.ListJobsOptions, options ...gitlab.RequestOptionFunc) ([]*gitlab.Job, *gitlab.Response, error) {
	return nil, makeResponse(http.StatusSeeOther), nil
}

func TestPipelineHandler(t *testing.T) {
	t.Run("Gets all pipeline jobs", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/pipeline/1", nil)
		server := createServer(fakeClient{listPipelineJobs: listPipelineJobs}, &ProjectInfo{}, MockAttachmentReader{})
		data := serveRequest(t, server, request, GetJobsResponse{})
		assert(t, data.SuccessResponse.Message, "Pipeline jobs retrieved")
		assert(t, data.SuccessResponse.Status, http.StatusOK)
	})

	t.Run("Disallows non-GET, non-POST methods", func(t *testing.T) {
		request := makeRequest(t, http.MethodPatch, "/pipeline/1", nil)
		server := createServer(fakeClient{listPipelineJobs: listPipelineJobs}, &ProjectInfo{}, MockAttachmentReader{})
		data := serveRequest(t, server, request, ErrorResponse{})
		checkBadMethod(t, *data, http.MethodGet, http.MethodPost)
	})

	t.Run("Handles errors from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/pipeline/1", nil)
		server := createServer(fakeClient{listPipelineJobs: listPipelineJobsErr}, &ProjectInfo{}, MockAttachmentReader{})
		data := serveRequest(t, server, request, ErrorResponse{})
		checkErrorFromGitlab(t, *data, "Could not get pipeline jobs")
	})

	t.Run("Handles non-200s from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/pipeline/1", nil)
		server := createServer(fakeClient{listPipelineJobs: listPipelineJobsNon200}, &ProjectInfo{}, MockAttachmentReader{})
		data := serveRequest(t, server, request, ErrorResponse{})
		checkNon200(t, *data, "Could not get pipeline jobs", "/pipeline")
	})
}
