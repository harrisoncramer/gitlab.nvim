package app

import (
	"net/http"
	"testing"

	"github.com/xanzy/go-gitlab"
	mock_main "gitlab.com/harrisoncramer/gitlab.nvim/cmd/mocks"
	"go.uber.org/mock/gomock"
)

var testReplyRequest = ReplyRequest{
	DiscussionId: "abc123",
	Reply:        "Some Reply",
	IsDraft:      false,
}

func TestReplyHandler(t *testing.T) {
	t.Run("Sends a reply", func(t *testing.T) {
		client := mock_main.NewMockClient(t)
		mock_main.WithMr(t, client)
		client.EXPECT().AddMergeRequestDiscussionNote(
			"",
			mock_main.MergeId,
			testReplyRequest.DiscussionId,
			gomock.Any(),
		).Return(&gitlab.Note{}, makeResponse(http.StatusOK), nil)

		request := makeRequest(t, http.MethodPost, "/mr/reply", testReplyRequest)
		server, _ := CreateRouterAndApi(client)

		data := serveRequest(t, server, request, ReplyResponse{})
		assert(t, data.SuccessResponse.Message, "Replied to comment")
		assert(t, data.SuccessResponse.Status, http.StatusOK)
	})

	t.Run("Disallows non-POST methods", func(t *testing.T) {
		client := mock_main.NewMockClient(t)
		mock_main.WithMr(t, client)

		request := makeRequest(t, http.MethodPut, "/mr/reply", testReplyRequest)
		server, _ := CreateRouterAndApi(client)

		data := serveRequest(t, server, request, ErrorResponse{})
		checkBadMethod(t, *data, http.MethodPost)
	})

	t.Run("Handles errors from Gitlab client", func(t *testing.T) {
		client := mock_main.NewMockClient(t)
		mock_main.WithMr(t, client)
		client.EXPECT().AddMergeRequestDiscussionNote(
			"",
			mock_main.MergeId,
			testReplyRequest.DiscussionId,
			gomock.Any(),
		).Return(nil, nil, errorFromGitlab)

		request := makeRequest(t, http.MethodPost, "/mr/reply", testReplyRequest)
		server, _ := CreateRouterAndApi(client)

		data := serveRequest(t, server, request, ErrorResponse{})
		checkErrorFromGitlab(t, *data, "Could not leave reply")
	})

	t.Run("Handles non-200s from Gitlab client", func(t *testing.T) {
		client := mock_main.NewMockClient(t)
		mock_main.WithMr(t, client)
		client.EXPECT().AddMergeRequestDiscussionNote(
			"",
			mock_main.MergeId,
			testReplyRequest.DiscussionId,
			gomock.Any(),
		).Return(nil, makeResponse(http.StatusSeeOther), nil)

		request := makeRequest(t, http.MethodPost, "/mr/reply", testReplyRequest)
		server, _ := CreateRouterAndApi(client)

		data := serveRequest(t, server, request, ErrorResponse{})
		checkNon200(t, *data, "Could not leave reply", "/mr/reply")
	})
}
