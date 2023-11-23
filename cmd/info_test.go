package main

import (
	"testing"
)

func TestInfoHandler(t *testing.T) {
	t.Run("Returns normal information", func(t *testing.T) {
		request := makeRequest(t, "GET", "/info", nil)
		client := FakeHandlerClient{Title: "Some Title"}
		var data InfoResponse
		data = serveRequest(t, client, request, data)
		assert(t, data.Info.Title, client.Title)
		assert(t, data.SuccessResponse.Message, "Merge requests retrieved")
		assert(t, data.SuccessResponse.Status, 200)
	})

	t.Run("Disallows non-GET method", func(t *testing.T) {
		request := makeRequest(t, "POST", "/info", nil)
		client := FakeHandlerClient{}
		var data ErrorResponse
		data = serveRequest(t, client, request, data)
		assert(t, data.Status, 405)
		assert(t, data.Message, "That request type is not allowed")
	})

	t.Run("Handles errors from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, "GET", "/info", nil)
		client := FakeHandlerClient{Error: "Some error from Gitlab"}
		var data ErrorResponse
		data = serveRequest(t, client, request, data)
		assert(t, data.Status, 500)
		assert(t, data.Message, "Could not get project info and initialize gitlab.nvim plugin")
		assert(t, data.Details, "Some error from Gitlab")
	})

	t.Run("Handles non-200s from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, "GET", "/info", nil)
		client := FakeHandlerClient{StatusCode: 302}
		var data ErrorResponse
		data = serveRequest(t, client, request, data)
		assert(t, data.Status, 302)
		assert(t, data.Message, "Gitlab returned non-200 status")
		assert(t, data.Details, "An error occured on the /info endpoint")
	})
}
