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
		request := makeRequest(t, http.MethodPost, "/comment", PostCommentRequest{})
		server := createServer(fakeClient{createMergeRequestDiscussion: createMergeRequestDiscussion}, &ProjectInfo{}, MockAttachmentReader{})
		data := serveRequest(t, server, request, CommentResponse{})
		assert(t, data.SuccessResponse.Message, "Note created successfully")
		assert(t, data.SuccessResponse.Status, http.StatusOK)
	})

	t.Run("Creates a new comment", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/comment", PostCommentRequest{FileName: "some_file.txt"})
		server := createServer(fakeClient{createMergeRequestDiscussion: createMergeRequestDiscussion}, &ProjectInfo{}, MockAttachmentReader{})
		data := serveRequest(t, server, request, CommentResponse{})
		assert(t, data.SuccessResponse.Message, "Comment created successfully")
		assert(t, data.SuccessResponse.Status, http.StatusOK)
	})

	t.Run("Creates a new multiline comment", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/comment", PostCommentRequest{
			FileName: "some_file.txt",
			LineRange: &LineRange{
				StartRange: &LinePosition{}, /* These would have real data */
				EndRange:   &LinePosition{},
			},
		})
		server := createServer(fakeClient{createMergeRequestDiscussion: createMergeRequestDiscussion}, &ProjectInfo{}, MockAttachmentReader{})
		data := serveRequest(t, server, request, CommentResponse{})
		assert(t, data.SuccessResponse.Message, "Multiline Comment created successfully")
		assert(t, data.SuccessResponse.Status, http.StatusOK)
	})

	t.Run("Handles errors from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/comment", PostCommentRequest{})
		server := createServer(fakeClient{createMergeRequestDiscussion: createMergeRequestDiscussionErr}, &ProjectInfo{}, MockAttachmentReader{})
		data := serveRequest(t, server, request, ErrorResponse{})
		assert(t, data.Message, "Could not create discussion")
		assert(t, data.Details, "Some error from Gitlab")
	})

	t.Run("Handles non-200s from Gitlab", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/comment", PostCommentRequest{})
		server := createServer(fakeClient{createMergeRequestDiscussion: createMergeRequestDiscussionNon200}, &ProjectInfo{}, MockAttachmentReader{})
		data := serveRequest(t, server, request, ErrorResponse{})
		assert(t, data.Message, "Could not create discussion")
		assert(t, data.Details, "An error occurred on the /comment endpoint")
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
		request := makeRequest(t, http.MethodDelete, "/comment", DeleteCommentRequest{})
		server := createServer(fakeClient{deleteMergeRequestDiscussionNote: deleteMergeRequestDiscussionNote}, &ProjectInfo{}, MockAttachmentReader{})
		data := serveRequest(t, server, request, CommentResponse{})
		assert(t, data.SuccessResponse.Message, "Comment deleted successfully")
		assert(t, data.SuccessResponse.Status, http.StatusOK)
	})

	t.Run("Handles errors from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodDelete, "/comment", DeleteCommentRequest{})
		server := createServer(fakeClient{deleteMergeRequestDiscussionNote: deleteMergeRequestDiscussionNoteErr}, &ProjectInfo{}, MockAttachmentReader{})
		data := serveRequest(t, server, request, ErrorResponse{})
		assert(t, data.Message, "Could not delete comment")
		assert(t, data.Details, "Some error from Gitlab")
	})

	t.Run("Handles non-200s from Gitlab", func(t *testing.T) {
		request := makeRequest(t, http.MethodDelete, "/comment", DeleteCommentRequest{})
		server := createServer(fakeClient{deleteMergeRequestDiscussionNote: deleteMergeRequestDiscussionNoteNon200}, &ProjectInfo{}, MockAttachmentReader{})
		data := serveRequest(t, server, request, ErrorResponse{})
		assert(t, data.Message, "Could not delete comment")
		assert(t, data.Details, "An error occurred on the /comment endpoint")
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
		request := makeRequest(t, http.MethodPatch, "/comment", EditCommentRequest{})
		server := createServer(fakeClient{updateMergeRequestDiscussionNote: updateMergeRequestDiscussionNote}, &ProjectInfo{}, MockAttachmentReader{})
		data := serveRequest(t, server, request, CommentResponse{})
		assert(t, data.SuccessResponse.Message, "Comment updated successfully")
		assert(t, data.SuccessResponse.Status, http.StatusOK)
	})

	t.Run("Handles errors from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodPatch, "/comment", EditCommentRequest{})
		server := createServer(fakeClient{updateMergeRequestDiscussionNote: updateMergeRequestDiscussionNoteErr}, &ProjectInfo{}, MockAttachmentReader{})
		data := serveRequest(t, server, request, ErrorResponse{})
		assert(t, data.Message, "Could not update comment")
		assert(t, data.Details, "Some error from Gitlab")
	})

	t.Run("Handles non-200s from Gitlab", func(t *testing.T) {
		request := makeRequest(t, http.MethodPatch, "/comment", EditCommentRequest{})
		server := createServer(fakeClient{updateMergeRequestDiscussionNote: updateMergeRequestDiscussionNoteNon200}, &ProjectInfo{}, MockAttachmentReader{})
		data := serveRequest(t, server, request, ErrorResponse{})
		assert(t, data.Message, "Could not update comment")
		assert(t, data.Details, "An error occurred on the /comment endpoint")
	})
}
