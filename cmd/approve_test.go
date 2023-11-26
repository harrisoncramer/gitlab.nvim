package main

import (
	"net/http"
	"testing"
)

func TestApproveHandler(t *testing.T) {
	t.Run("Approves merge request", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/approve", nil)
		client := FakeHandlerClient{}
		data := serveRequest(t, approveHandler, client, request, SuccessResponse{})
		assert(t, data.Message, "Approved MR")
		assert(t, data.Status, http.StatusOK)
	})

	t.Run("Disallows non-POST method", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/approve", nil)
		client := FakeHandlerClient{}
		data := serveRequest(t, approveHandler, client, request, ErrorResponse{})
		assert(t, data.Status, http.StatusMethodNotAllowed)
		assert(t, data.Details, "Invalid request type")
		assert(t, data.Message, "Expected POST")
	})

	t.Run("Handles errors from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/approve", nil)
		client := FakeHandlerClient{Error: "Some error from Gitlab"}
		data := serveRequest(t, approveHandler, client, request, ErrorResponse{})
		assert(t, data.Status, http.StatusInternalServerError)
		assert(t, data.Message, "Could not approve merge request")
		assert(t, data.Details, "Some error from Gitlab")
	})

	t.Run("Handles non-200s from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/approve", nil)
		client := FakeHandlerClient{StatusCode: http.StatusSeeOther}
		data := serveRequest(t, approveHandler, client, request, ErrorResponse{})
		assert(t, data.Status, http.StatusSeeOther)
		assert(t, data.Message, "Could not approve merge request")
		assert(t, data.Details, "An error occurred on the /approve endpoint")
	})
}
