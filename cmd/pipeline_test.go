package main

import (
	"net/http"
	"testing"
)

func TestPipelineHandler(t *testing.T) {
	t.Run("Disallows bad method type (non-GET, non-POST)", func(t *testing.T) {
		request := makeRequest(t, http.MethodPatch, "/pipeline/1", nil)
		client := FakeHandlerClient{}
		data := serveRequest(t, PipelineHandler, client, request, ErrorResponse{})
		assert(t, data.Status, http.StatusMethodNotAllowed)
		assert(t, data.Details, "Invalid request type")
		assert(t, data.Message, "Expected GET or POST")
	})

	t.Run("GET: Returns pipeline jobs", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/pipeline/1", nil)
		client := FakeHandlerClient{}
		data := serveRequest(t, PipelineHandler, client, request, GetJobsResponse{})
		assert(t, data.SuccessResponse.Message, "Pipeline jobs retrieved")
		assert(t, data.SuccessResponse.Status, http.StatusOK)
	})

	t.Run("GET: Handles errors from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/pipeline/1", nil)
		client := FakeHandlerClient{Error: "Some error from Gitlab"}
		data := serveRequest(t, PipelineHandler, client, request, ErrorResponse{})
		assert(t, data.Status, http.StatusInternalServerError)
		assert(t, data.Message, "Could not get pipeline jobs")
		assert(t, data.Details, "Some error from Gitlab")
	})

	t.Run("GET: Handles non-200s from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/pipeline/1", nil)
		client := FakeHandlerClient{StatusCode: http.StatusSeeOther}
		data := serveRequest(t, PipelineHandler, client, request, ErrorResponse{})
		assert(t, data.Status, http.StatusSeeOther)
		assert(t, data.Message, "Could not get pipeline jobs")
		assert(t, data.Details, "An error occurred on the /pipeline endpoint")
	})
}
