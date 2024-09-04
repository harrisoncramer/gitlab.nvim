package app

import (
	"net/http"
	"testing"

	"github.com/xanzy/go-gitlab"
	mock_main "gitlab.com/harrisoncramer/gitlab.nvim/cmd/mocks"
	"go.uber.org/mock/gomock"
)

func TestMembersHandler(t *testing.T) {
	t.Run("Returns project members", func(t *testing.T) {
		client := mock_main.NewMockClient(t)
		client.EXPECT().ListAllProjectMembers("", gomock.Any()).Return([]*gitlab.ProjectMember{}, makeResponse(http.StatusOK), nil)

		request := makeRequest(t, http.MethodGet, "/project/members", nil)
		server := CreateRouter(client)
		data := serveRequest(t, server, request, ProjectMembersResponse{})

		assert(t, data.SuccessResponse.Message, "Project members retrieved")
		assert(t, data.SuccessResponse.Status, http.StatusOK)
	})

	t.Run("Disallows non-GET method", func(t *testing.T) {
		client := mock_main.NewMockClient(t)

		request := makeRequest(t, http.MethodPost, "/project/members", nil)
		server := CreateRouter(client)

		data := serveRequest(t, server, request, ErrorResponse{})
		checkBadMethod(t, *data, http.MethodGet)
	})

	t.Run("Handles errors from Gitlab client", func(t *testing.T) {
		client := mock_main.NewMockClient(t)
		client.EXPECT().ListAllProjectMembers("", gomock.Any()).Return(nil, nil, errorFromGitlab)

		request := makeRequest(t, http.MethodGet, "/project/members", nil)
		server := CreateRouter(client)
		data := serveRequest(t, server, request, ErrorResponse{})

		checkErrorFromGitlab(t, *data, "Could not retrieve project members")
	})

	t.Run("Handles non-200s from Gitlab client", func(t *testing.T) {
		client := mock_main.NewMockClient(t)
		client.EXPECT().ListAllProjectMembers("", gomock.Any()).Return(nil, makeResponse(http.StatusSeeOther), nil)

		request := makeRequest(t, http.MethodGet, "/project/members", nil)
		server := CreateRouter(client)
		data := serveRequest(t, server, request, ErrorResponse{})

		checkNon200(t, *data, "Could not retrieve project members", "/project/members")
	})
}
