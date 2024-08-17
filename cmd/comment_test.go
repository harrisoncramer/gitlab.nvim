package main

import (
	"errors"
	"net/http"
	"testing"

	"github.com/xanzy/go-gitlab"
	mock_main "gitlab.com/harrisoncramer/gitlab.nvim/cmd/mocks"
)

var testCommentCreationData = PostCommentRequest{
	Comment: "Some comment",
}

var testCommentDeletionData = DeleteCommentRequest{
	NoteId:       3,
	DiscussionId: "abc123",
}

func TestPostComment(t *testing.T) {
	t.Run("Creates a new note (unlinked comment)", func(t *testing.T) {
		client := mock_main.NewMockClient(t)
		mock_main.WithMr(t, client, mock_main.MergeId)
		client.EXPECT().CreateMergeRequestDiscussion(
			"",
			mock_main.MergeId,
			&gitlab.CreateMergeRequestDiscussionOptions{Body: gitlab.Ptr(testCommentCreationData.Comment)},
		).Return(&gitlab.Discussion{Notes: []*gitlab.Note{{}}}, makeResponse(http.StatusOK), nil)

		request := makeRequest(t, http.MethodPost, "/mr/comment", testCommentCreationData)
		server, _ := CreateRouterAndApi(client)
		data := serveRequest(t, server, request, CommentResponse{})

		assert(t, data.SuccessResponse.Message, "Comment created successfully")
		assert(t, data.SuccessResponse.Status, http.StatusOK)
	})

	t.Run("Creates a new comment", func(t *testing.T) {
		// Re-create comment creation data to avoid mutating this variable in other tests
		testCommentCreationData := PostCommentRequest{
			Comment: "Some comment",
			PositionData: PositionData{
				FileName: "file.txt",
			},
		}

		client := mock_main.NewMockClient(t)
		mock_main.WithMr(t, client, mock_main.MergeId)
		client.EXPECT().CreateMergeRequestDiscussion(
			"",
			mock_main.MergeId,
			&gitlab.CreateMergeRequestDiscussionOptions{
				Body:     gitlab.Ptr(testCommentCreationData.Comment),
				Position: buildCommentPosition(CommentWithPosition{testCommentCreationData.PositionData}),
			},
		).Return(&gitlab.Discussion{Notes: []*gitlab.Note{{}}}, makeResponse(http.StatusOK), nil)

		request := makeRequest(t, http.MethodPost, "/mr/comment", testCommentCreationData)

		server, _ := CreateRouterAndApi(client)
		data := serveRequest(t, server, request, CommentResponse{})
		assert(t, data.SuccessResponse.Message, "Comment created successfully")
		assert(t, data.SuccessResponse.Status, http.StatusOK)
	})

	t.Run("Handles errors from Gitlab client", func(t *testing.T) {
		client := mock_main.NewMockClient(t)
		mock_main.WithMr(t, client, mock_main.MergeId)
		client.EXPECT().CreateMergeRequestDiscussion(
			"",
			mock_main.MergeId,
			&gitlab.CreateMergeRequestDiscussionOptions{Body: gitlab.Ptr(testCommentCreationData.Comment)},
		).Return(nil, nil, errors.New("Some error from Gitlab"))

		request := makeRequest(t, http.MethodPost, "/mr/comment", testCommentCreationData)
		server, _ := CreateRouterAndApi(client)
		data := serveRequest(t, server, request, ErrorResponse{})

		checkErrorFromGitlab(t, *data, "Could not create discussion")
	})

	t.Run("Handles non-200s from Gitlab", func(t *testing.T) {
		client := mock_main.NewMockClient(t)
		mock_main.WithMr(t, client, mock_main.MergeId)
		client.EXPECT().CreateMergeRequestDiscussion(
			"",
			mock_main.MergeId,
			&gitlab.CreateMergeRequestDiscussionOptions{Body: gitlab.Ptr(testCommentCreationData.Comment)},
		).Return(nil, makeResponse(http.StatusSeeOther), nil)

		request := makeRequest(t, http.MethodPost, "/mr/comment", testCommentCreationData)
		server, _ := CreateRouterAndApi(client)
		data := serveRequest(t, server, request, ErrorResponse{})

		checkNon200(t, *data, "Could not create discussion", "/mr/comment")
	})
}

func TestDeleteComment(t *testing.T) {
	t.Run("Deletes a comment", func(t *testing.T) {
		client := mock_main.NewMockClient(t)
		mock_main.WithMr(t, client, mock_main.MergeId)
		client.EXPECT().DeleteMergeRequestDiscussionNote("", mock_main.MergeId, testCommentDeletionData.DiscussionId, testCommentDeletionData.NoteId).Return(makeResponse(http.StatusOK), nil)

		request := makeRequest(t, http.MethodDelete, "/mr/comment", testCommentDeletionData)
		server, _ := CreateRouterAndApi(client)
		data := serveRequest(t, server, request, CommentResponse{})

		assert(t, data.SuccessResponse.Message, "Comment deleted successfully")
		assert(t, data.SuccessResponse.Status, http.StatusOK)
	})

	t.Run("Handles errors from Gitlab client", func(t *testing.T) {
		client := mock_main.NewMockClient(t)
		mock_main.WithMr(t, client, mock_main.MergeId)
		client.EXPECT().DeleteMergeRequestDiscussionNote("", mock_main.MergeId, testCommentDeletionData.DiscussionId, testCommentDeletionData.NoteId).Return(nil, errors.New("Some error from Gitlab"))

		request := makeRequest(t, http.MethodDelete, "/mr/comment", testCommentDeletionData)
		server, _ := CreateRouterAndApi(client)
		data := serveRequest(t, server, request, ErrorResponse{})

		checkErrorFromGitlab(t, *data, "Could not delete comment")
	})

	t.Run("Handles non-200s from Gitlab", func(t *testing.T) {
		client := mock_main.NewMockClient(t)
		mock_main.WithMr(t, client, mock_main.MergeId)
		client.EXPECT().DeleteMergeRequestDiscussionNote("", mock_main.MergeId, testCommentDeletionData.DiscussionId, testCommentDeletionData.NoteId).Return(makeResponse(http.StatusSeeOther), nil)

		request := makeRequest(t, http.MethodDelete, "/mr/comment", testCommentDeletionData)
		server, _ := CreateRouterAndApi(client)
		data := serveRequest(t, server, request, ErrorResponse{})

		checkNon200(t, *data, "Could not delete comment", "/mr/comment")
	})
}

func updateMergeRequestDiscussionNote(pid interface{}, mergeRequest int, discussion string, note int, opt *gitlab.UpdateMergeRequestDiscussionNoteOptions, options ...gitlab.RequestOptionFunc) (*gitlab.Note, *gitlab.Response, error) {
	return &gitlab.Note{}, makeResponse(http.StatusOK), nil
}

func updateMergeRequestDiscussionNoteErr(pid interface{}, mergeRequest int, discussion string, note int, opt *gitlab.UpdateMergeRequestDiscussionNoteOptions, options ...gitlab.RequestOptionFunc) (*gitlab.Note, *gitlab.Response, error) {
	return nil, nil, errors.New("Some error from Gitlab")
}

func updateMergeRequestDiscussionNoteNon200(pid interface{}, mergeRequest int, discussion string, note int, opt *gitlab.UpdateMergeRequestDiscussionNoteOptions, options ...gitlab.RequestOptionFunc) (*gitlab.Note, *gitlab.Response, error) {
	return nil, makeResponse(http.StatusSeeOther), nil
}

func TestEditComment(t *testing.T) {
	t.Run("Edits a comment", func(t *testing.T) {
		request := makeRequest(t, http.MethodPatch, "/mr/comment", EditCommentRequest{})
		server, _ := CreateRouterAndApi(fakeClient{updateMergeRequestDiscussionNote: updateMergeRequestDiscussionNote})
		data := serveRequest(t, server, request, CommentResponse{})
		assert(t, data.SuccessResponse.Message, "Comment updated successfully")
		assert(t, data.SuccessResponse.Status, http.StatusOK)
	})

	t.Run("Handles errors from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodPatch, "/mr/comment", EditCommentRequest{})
		server, _ := CreateRouterAndApi(fakeClient{updateMergeRequestDiscussionNote: updateMergeRequestDiscussionNoteErr})
		data := serveRequest(t, server, request, ErrorResponse{})
		checkErrorFromGitlab(t, *data, "Could not update comment")
	})

	t.Run("Handles non-200s from Gitlab", func(t *testing.T) {
		request := makeRequest(t, http.MethodPatch, "/mr/comment", EditCommentRequest{})
		server, _ := CreateRouterAndApi(fakeClient{updateMergeRequestDiscussionNote: updateMergeRequestDiscussionNoteNon200})
		data := serveRequest(t, server, request, ErrorResponse{})
		checkNon200(t, *data, "Could not update comment", "/mr/comment")
	})
}
