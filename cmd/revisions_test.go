package main

import (
	"net/http"
	"testing"
)

func TestRevisionsHandler(t *testing.T) {
	t.Run("Returns normal revisions", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/mr/revisions", nil)
		client := FakeHandlerClient{}
		data := serveRequest(t, revisionsHandler, client, request, RevisionsResponse{})
		assert(t, data.SuccessResponse.Message, "Revisions fetched successfully")
		assert(t, data.SuccessResponse.Status, http.StatusOK)
	})

	t.Run("Disallows non-GET method", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/mr/revisions", nil)
		client := FakeHandlerClient{}
		data := serveRequest(t, revisionsHandler, client, request, ErrorResponse{})
		assert(t, data.Status, http.StatusMethodNotAllowed)
		assert(t, data.Details, "Invalid request type")
		assert(t, data.Message, "Expected GET")
	})

	t.Run("Handles errors from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/mr/revisions", nil)
		client := FakeHandlerClient{Error: "Some error from Gitlab"}
		data := serveRequest(t, revisionsHandler, client, request, ErrorResponse{})
		assert(t, data.Status, http.StatusInternalServerError)
		assert(t, data.Message, "Could not get diff version info")
		assert(t, data.Details, "Some error from Gitlab")
	})

	t.Run("Handles non-200s from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/mr/revisions", nil)
		client := FakeHandlerClient{StatusCode: http.StatusSeeOther}
		data := serveRequest(t, revisionsHandler, client, request, ErrorResponse{})
		assert(t, data.Status, http.StatusSeeOther)
		assert(t, data.Message, "Could not get diff version info")
		assert(t, data.Details, "An error occurred on the /mr/revisions endpoint")
	})
}
