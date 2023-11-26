package main

import (
	"net/http"
	"testing"
)

func TestRevokeHandler(t *testing.T) {
	t.Run("Returns normal information", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/revoke", nil)
		client := FakeHandlerClient{}
		data := serveRequest(t, revokeHandler, client, request, SuccessResponse{})
		assert(t, data.Message, "Success! Revoked MR approval")
		assert(t, data.Status, http.StatusOK)
	})

	t.Run("Disallows non-POST method", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/revoke", nil)
		client := FakeHandlerClient{}
		data := serveRequest(t, revokeHandler, client, request, ErrorResponse{})
		assert(t, data.Status, http.StatusMethodNotAllowed)
		assert(t, data.Details, "Invalid request type")
		assert(t, data.Message, "Expected POST")
	})

	t.Run("Handles errors from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/revoke", nil)
		client := FakeHandlerClient{Error: "Some error from Gitlab"}
		data := serveRequest(t, revokeHandler, client, request, ErrorResponse{})
		assert(t, data.Status, http.StatusInternalServerError)
		assert(t, data.Message, "Could not revoke approval")
		assert(t, data.Details, "Some error from Gitlab")
	})

	t.Run("Handles non-200s from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/revoke", nil)
		client := FakeHandlerClient{StatusCode: http.StatusSeeOther}
		data := serveRequest(t, revokeHandler, client, request, ErrorResponse{})
		assert(t, data.Status, http.StatusSeeOther)
		assert(t, data.Message, "Could not revoke approval")
		assert(t, data.Details, "An error occurred on the /revoke endpoint")
	})
}
