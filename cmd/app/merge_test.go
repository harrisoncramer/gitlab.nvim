package app

import (
	"net/http"
	"testing"

	"github.com/xanzy/go-gitlab"
	mock_main "gitlab.com/harrisoncramer/gitlab.nvim/cmd/mocks"
	"go.uber.org/mock/gomock"
)

var testAcceptMergeRequestPayload = AcceptMergeRequestRequest{
	Squash:        false,
	SquashMessage: "Squash me!",
	DeleteBranch:  false,
}

func TestAcceptAndMergeHandler(t *testing.T) {
	t.Run("Accepts and merges a merge request", func(t *testing.T) {
		client := mock_main.NewMockClient(t)
		mock_main.WithMr(t, client)
		client.EXPECT().AcceptMergeRequest("", mock_main.MergeId, gomock.Any()).Return(&gitlab.MergeRequest{}, makeResponse(http.StatusOK), nil)

		request := makeRequest(t, http.MethodPost, "/mr/merge", testAcceptMergeRequestPayload)
		server, _ := CreateRouterAndApi(client)
		data := serveRequest(t, server, request, SuccessResponse{})

		assert(t, data.Message, "MR merged successfully")
		assert(t, data.Status, http.StatusOK)
	})

	t.Run("Disallows non-POST methods", func(t *testing.T) {
		client := mock_main.NewMockClient(t)
		mock_main.WithMr(t, client)
		client.EXPECT().AcceptMergeRequest("", mock_main.MergeId, gomock.Any()).Return(&gitlab.MergeRequest{}, makeResponse(http.StatusOK), nil)

		request := makeRequest(t, http.MethodPatch, "/mr/merge", testAcceptMergeRequestPayload)
		server, _ := CreateRouterAndApi(client)
		data := serveRequest(t, server, request, ErrorResponse{})

		checkBadMethod(t, *data, http.MethodPost)
	})

	t.Run("Handles errors from Gitlab client", func(t *testing.T) {
		client := mock_main.NewMockClient(t)
		mock_main.WithMr(t, client)
		client.EXPECT().AcceptMergeRequest("", mock_main.MergeId, gomock.Any()).Return(nil, nil, errorFromGitlab)

		request := makeRequest(t, http.MethodPost, "/mr/merge", testAcceptMergeRequestPayload)
		server, _ := CreateRouterAndApi(client)
		data := serveRequest(t, server, request, ErrorResponse{})

		checkErrorFromGitlab(t, *data, "Could not merge MR")
	})

	t.Run("Handles non-200s from Gitlab client", func(t *testing.T) {
		client := mock_main.NewMockClient(t)
		mock_main.WithMr(t, client)
		client.EXPECT().AcceptMergeRequest("", mock_main.MergeId, gomock.Any()).Return(nil, makeResponse(http.StatusSeeOther), nil)

		request := makeRequest(t, http.MethodPost, "/mr/merge", testAcceptMergeRequestPayload)
		server, _ := CreateRouterAndApi(client)
		data := serveRequest(t, server, request, ErrorResponse{})

		checkNon200(t, *data, "Could not merge MR", "/mr/merge")
	})
}
