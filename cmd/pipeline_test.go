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

func retryPipelineBuild(pid interface{}, pipeline int, options ...gitlab.RequestOptionFunc) (*gitlab.Pipeline, *gitlab.Response, error) {
	return &gitlab.Pipeline{}, makeResponse(http.StatusOK), nil
}

func retryPipelineBuildErr(pid interface{}, pipeline int, options ...gitlab.RequestOptionFunc) (*gitlab.Pipeline, *gitlab.Response, error) {
	return nil, nil, errors.New("Some error from Gitlab")
}

func retryPipelineBuildNon200(pid interface{}, pipeline int, options ...gitlab.RequestOptionFunc) (*gitlab.Pipeline, *gitlab.Response, error) {
	return nil, makeResponse(http.StatusSeeOther), nil
}

func TestPipelineHandler(t *testing.T) {
	t.Run("Gets all pipeline jobs", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/pipeline/1", nil)
		server, _ := createRouterAndApi(fakeClient{listPipelineJobs: listPipelineJobs})
		data := serveRequest(t, server, request, GetJobsResponse{})
		assert(t, data.SuccessResponse.Message, "Pipeline jobs retrieved")
		assert(t, data.SuccessResponse.Status, http.StatusOK)
	})

	t.Run("Disallows non-GET, non-POST methods", func(t *testing.T) {
		request := makeRequest(t, http.MethodPatch, "/pipeline/1", nil)
		server, _ := createRouterAndApi(fakeClient{listPipelineJobs: listPipelineJobs})
		data := serveRequest(t, server, request, ErrorResponse{})
		checkBadMethod(t, *data, http.MethodGet, http.MethodPost)
	})

	t.Run("Handles errors from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/pipeline/1", nil)
		server, _ := createRouterAndApi(fakeClient{listPipelineJobs: listPipelineJobsErr})
		data := serveRequest(t, server, request, ErrorResponse{})
		checkErrorFromGitlab(t, *data, "Could not get pipeline jobs")
	})

	t.Run("Handles non-200s from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/pipeline/1", nil)
		server, _ := createRouterAndApi(fakeClient{listPipelineJobs: listPipelineJobsNon200})
		data := serveRequest(t, server, request, ErrorResponse{})
		checkNon200(t, *data, "Could not get pipeline jobs", "/pipeline")
	})

	t.Run("Retriggers pipeline", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/pipeline/1", nil)
		server, _ := createRouterAndApi(fakeClient{retryPipelineBuild: retryPipelineBuild})
		data := serveRequest(t, server, request, GetJobsResponse{})
		assert(t, data.SuccessResponse.Message, "Pipeline retriggered")
		assert(t, data.SuccessResponse.Status, http.StatusOK)
	})

	t.Run("Handles errors from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/pipeline/1", nil)
		server, _ := createRouterAndApi(fakeClient{retryPipelineBuild: retryPipelineBuildErr})
		data := serveRequest(t, server, request, ErrorResponse{})
		checkErrorFromGitlab(t, *data, "Could not retrigger pipeline")
	})

	t.Run("Handles non-200s from Gitlab client on retrigger", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/pipeline/1", nil)
		server, _ := createRouterAndApi(fakeClient{retryPipelineBuild: retryPipelineBuildNon200})
		data := serveRequest(t, server, request, ErrorResponse{})
		checkNon200(t, *data, "Could not retrigger pipeline", "/pipeline")
	})
}
