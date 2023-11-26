package main

import (
	"net/http"
	"testing"
)

func TestInfoHandler(t *testing.T) {
	t.Run("Returns normal information", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/info", nil)
		client := FakeHandlerClient{Title: "Some Title"}
		data := serveRequest(t, InfoHandler, client, request, InfoResponse{})
		assert(t, data.Info.Title, "Some Title")
		assert(t, data.SuccessResponse.Message, "Merge requests retrieved")
		assert(t, data.SuccessResponse.Status, http.StatusOK)
	})

	t.Run("Disallows non-GET method", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/info", nil)
		client := FakeHandlerClient{}
		data := serveRequest(t, InfoHandler, client, request, ErrorResponse{})
		assert(t, data.Status, http.StatusMethodNotAllowed)
		assert(t, data.Details, "Invalid request type")
		assert(t, data.Message, "Expected GET")
	})

	t.Run("Handles errors from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/info", nil)
		client := FakeHandlerClient{Error: "Some error from Gitlab"}
		data := serveRequest(t, InfoHandler, client, request, ErrorResponse{})
		assert(t, data.Status, http.StatusInternalServerError)
		assert(t, data.Message, "Could not get project info and initialize gitlab.nvim plugin")
		assert(t, data.Details, "Some error from Gitlab")
	})

	t.Run("Handles non-200s from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/info", nil)
		client := FakeHandlerClient{StatusCode: http.StatusSeeOther}
		data := serveRequest(t, InfoHandler, client, request, ErrorResponse{})
		assert(t, data.Status, http.StatusSeeOther)
		assert(t, data.Message, "Gitlab returned non-200 status")
		assert(t, data.Details, "An error occurred on the /info endpoint")
	})
}
