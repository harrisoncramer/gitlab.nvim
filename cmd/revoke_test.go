package main

import (
	"testing"
)

func TestRevokeHandler(t *testing.T) {
	t.Run("Returns normal information", func(t *testing.T) {
		request := makeRequest(t, "POST", "/revoke", nil)
		client := FakeHandlerClient{}
		var data SuccessResponse
		data = serveRequest(t, RevokeHandler, client, request, data)
		assert(t, data.Message, "Success! Revoked MR approval")
		assert(t, data.Status, 200)
	})

	t.Run("Disallows non-POST method", func(t *testing.T) {
		request := makeRequest(t, "GET", "/revoke", nil)
		client := FakeHandlerClient{}
		var data ErrorResponse
		data = serveRequest(t, RevokeHandler, client, request, data)
		assert(t, data.Status, 405)
		assert(t, data.Message, "That request type is not allowed")
	})

	t.Run("Handles errors from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, "POST", "/revoke", nil)
		client := FakeHandlerClient{Error: "Some error from Gitlab"}
		var data ErrorResponse
		data = serveRequest(t, RevokeHandler, client, request, data)
		assert(t, data.Status, 500)
		assert(t, data.Message, "Could not revoke approval")
		assert(t, data.Details, "Some error from Gitlab")
	})

	t.Run("Handles non-200s from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, "POST", "/revoke", nil)
		client := FakeHandlerClient{StatusCode: 302}
		var data ErrorResponse
		data = serveRequest(t, RevokeHandler, client, request, data)
		assert(t, data.Status, 302)
		assert(t, data.Message, "Gitlab returned non-200 status")
		assert(t, data.Details, "An error occured on the /revoke endpoint")
	})
}
