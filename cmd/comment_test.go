package main

import (
	"errors"
	"net/http"
	"testing"

	"github.com/xanzy/go-gitlab"
)

func createMergeRequestDiscussion(pid interface{}, mergeRequest int, opt *gitlab.CreateMergeRequestDiscussionOptions, options ...gitlab.RequestOptionFunc) (*gitlab.Discussion, *gitlab.Response, error) {
	return &gitlab.Discussion{Notes: []*gitlab.Note{{}}}, makeResponse(http.StatusOK), nil
}

func createMergeRequestDiscussionNon200(pid interface{}, mergeRequest int, opt *gitlab.CreateMergeRequestDiscussionOptions, options ...gitlab.RequestOptionFunc) (*gitlab.Discussion, *gitlab.Response, error) {
	return nil, makeResponse(http.StatusSeeOther), nil
}

func createMergeRequestDiscussionErr(pid interface{}, mergeRequest int, opt *gitlab.CreateMergeRequestDiscussionOptions, options ...gitlab.RequestOptionFunc) (*gitlab.Discussion, *gitlab.Response, error) {
	return nil, nil, errors.New("Some error from Gitlab")
}

func TestPostComment(t *testing.T) {
	t.Run("Creates a new note (unlinked comment)", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/mr/comment", PostCommentRequest{})
		server, _ := CreateRouterAndApi(fakeClient{createMergeRequestDiscussion: createMergeRequestDiscussion})
		data := serveRequest(t, server, request, CommentResponse{})
		assert(t, data.SuccessResponse.Message, "Comment created successfully")
		assert(t, data.SuccessResponse.Status, http.StatusOK)
	})

	t.Run("Creates a new comment", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/mr/comment", PostCommentRequest{
			PositionData: PositionData{
				FileName: "some_file.txt",
			},
		})
		server, _ := CreateRouterAndApi(fakeClient{createMergeRequestDiscussion: createMergeRequestDiscussion})
		data := serveRequest(t, server, request, CommentResponse{})
		assert(t, data.SuccessResponse.Message, "Comment created successfully")
		assert(t, data.SuccessResponse.Status, http.StatusOK)
	})

	t.Run("Creates a new multiline comment", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/mr/comment", PostCommentRequest{
			PositionData: PositionData{
				FileName: "some_file.txt",
				LineRange: &LineRange{
					StartRange: &LinePosition{}, /* These would have real data */
					EndRange:   &LinePosition{},
				},
			},
		})
		server, _ := CreateRouterAndApi(fakeClient{createMergeRequestDiscussion: createMergeRequestDiscussion})
		data := serveRequest(t, server, request, CommentResponse{})
		assert(t, data.SuccessResponse.Message, "Comment created successfully")
		assert(t, data.SuccessResponse.Status, http.StatusOK)
	})

	t.Run("Handles errors from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/mr/comment", PostCommentRequest{})
		server, _ := CreateRouterAndApi(fakeClient{createMergeRequestDiscussion: createMergeRequestDiscussionErr})
		data := serveRequest(t, server, request, ErrorResponse{})
		checkErrorFromGitlab(t, *data, "Could not create discussion")
	})

	t.Run("Handles non-200s from Gitlab", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/mr/comment", PostCommentRequest{})
		server, _ := CreateRouterAndApi(fakeClient{createMergeRequestDiscussion: createMergeRequestDiscussionNon200})
		data := serveRequest(t, server, request, ErrorResponse{})
		checkNon200(t, *data, "Could not create discussion", "/mr/comment")
	})
}

func deleteMergeRequestDiscussionNote(pid interface{}, mergeRequest int, discussion string, note int, options ...gitlab.RequestOptionFunc) (*gitlab.Response, error) {
	return makeResponse(http.StatusOK), nil
}

func deleteMergeRequestDiscussionNoteErr(pid interface{}, mergeRequest int, discussion string, note int, options ...gitlab.RequestOptionFunc) (*gitlab.Response, error) {
	return nil, errors.New("Some error from Gitlab")
}

func deleteMergeRequestDiscussionNoteNon200(pid interface{}, mergeRequest int, discussion string, note int, options ...gitlab.RequestOptionFunc) (*gitlab.Response, error) {
	return makeResponse(http.StatusSeeOther), nil
}

func TestDeleteComment(t *testing.T) {
	t.Run("Deletes a comment", func(t *testing.T) {
		request := makeRequest(t, http.MethodDelete, "/mr/comment", DeleteCommentRequest{})
		server, _ := CreateRouterAndApi(fakeClient{deleteMergeRequestDiscussionNote: deleteMergeRequestDiscussionNote})
		data := serveRequest(t, server, request, CommentResponse{})
		assert(t, data.SuccessResponse.Message, "Comment deleted successfully")
		assert(t, data.SuccessResponse.Status, http.StatusOK)
	})

	t.Run("Handles errors from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodDelete, "/mr/comment", DeleteCommentRequest{})
		server, _ := CreateRouterAndApi(fakeClient{deleteMergeRequestDiscussionNote: deleteMergeRequestDiscussionNoteErr})
		data := serveRequest(t, server, request, ErrorResponse{})
		checkErrorFromGitlab(t, *data, "Could not delete comment")
	})

	t.Run("Handles non-200s from Gitlab", func(t *testing.T) {
		request := makeRequest(t, http.MethodDelete, "/mr/comment", DeleteCommentRequest{})
		server, _ := CreateRouterAndApi(fakeClient{deleteMergeRequestDiscussionNote: deleteMergeRequestDiscussionNoteNon200})
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
