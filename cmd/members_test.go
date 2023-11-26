package main

import (
	"net/http"
	"testing"
)

func TestMembersHandler(t *testing.T) {
	t.Run("Returns project members", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/project/members", nil)
		client := FakeHandlerClient{}
		data := serveRequest(t, ProjectMembersHandler, client, request, ProjectMembersResponse{})
		assert(t, data.SuccessResponse.Message, "Project members retrieved")
		assert(t, data.SuccessResponse.Status, http.StatusOK)
	})

	t.Run("Disallows non-GET method", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/project/members", nil)
		client := FakeHandlerClient{}
		data := serveRequest(t, ProjectMembersHandler, client, request, ErrorResponse{})
		assert(t, data.Status, http.StatusMethodNotAllowed)
		assert(t, data.Details, "Invalid request type")
		assert(t, data.Message, "Expected GET")
	})

	t.Run("Handles errors from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/project/members", nil)
		client := FakeHandlerClient{Error: "Some error from Gitlab"}
		data := serveRequest(t, ProjectMembersHandler, client, request, ErrorResponse{})
		assert(t, data.Status, http.StatusInternalServerError)
		assert(t, data.Message, "Could not retrieve project members")
		assert(t, data.Details, "Some error from Gitlab")
	})

	t.Run("Handles non-200s from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/project/members", nil)
		client := FakeHandlerClient{StatusCode: http.StatusSeeOther}
		data := serveRequest(t, ProjectMembersHandler, client, request, ErrorResponse{})
		assert(t, data.Status, http.StatusSeeOther)
		assert(t, data.Message, "Gitlab returned non-200 status")
		assert(t, data.Details, "An error occurred on the /project/members endpoint")
	})
}
