package main

import (
	"net/http"
	"testing"

	"github.com/xanzy/go-gitlab"
	mock_main "gitlab.com/harrisoncramer/gitlab.nvim/cmd/mocks"
)

func TestApproveHandler(t *testing.T) {
	t.Run("Approves merge request", func(t *testing.T) {
		client := mock_main.NewMockClient(t)
		mock_main.WithMr(t, client, mock_main.MergeId)
		client.EXPECT().ApproveMergeRequest("", mock_main.MergeId, nil, nil).Return(&gitlab.MergeRequestApprovals{}, makeResponse(http.StatusOK), nil)

		request := makeRequest(t, http.MethodPost, "/mr/approve", nil)
		server, _ := CreateRouterAndApi(client)
		data := serveRequest(t, server, request, SuccessResponse{})

		assert(t, data.Message, "Approved MR")
		assert(t, data.Status, http.StatusOK)
	})

	t.Run("Disallows non-POST method", func(t *testing.T) {
		client := mock_main.NewMockClient(t)
		mock_main.WithMr(t, client, mock_main.MergeId)
		client.EXPECT().ApproveMergeRequest("", mock_main.MergeId, nil, nil).Return(&gitlab.MergeRequestApprovals{}, makeResponse(http.StatusOK), nil)

		request := makeRequest(t, http.MethodPut, "/mr/approve", nil)
		server, _ := CreateRouterAndApi(client)
		data := serveRequest(t, server, request, ErrorResponse{})
		checkBadMethod(t, *data, http.MethodPost)
	})

	t.Run("Handles errors from Gitlab client", func(t *testing.T) {
		client := mock_main.NewMockClient(t)
		mock_main.WithMr(t, client, mock_main.MergeId)
		client.EXPECT().ApproveMergeRequest("", mock_main.MergeId, nil, nil).Return(nil, nil, errorFromGitlab)

		request := makeRequest(t, http.MethodPost, "/mr/approve", nil)
		server, _ := CreateRouterAndApi(client)
		data := serveRequest(t, server, request, ErrorResponse{})

		checkErrorFromGitlab(t, *data, "Could not approve merge request")
	})

	t.Run("Handles non-200s from Gitlab client", func(t *testing.T) {
		client := mock_main.NewMockClient(t)
		mock_main.WithMr(t, client, mock_main.MergeId)
		client.EXPECT().ApproveMergeRequest("", mock_main.MergeId, nil, nil).Return(nil, makeResponse(http.StatusSeeOther), nil)

		request := makeRequest(t, http.MethodPost, "/mr/approve", nil)
		server, _ := CreateRouterAndApi(client)
		data := serveRequest(t, server, request, ErrorResponse{})

		checkNon200(t, *data, "Could not approve merge request", "/mr/approve")
	})
}
