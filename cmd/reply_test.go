package main

import (
	"errors"
	"net/http"
	"testing"

	"github.com/xanzy/go-gitlab"
)

func addMergeRequestDiscussionNote(pid interface{}, mergeRequest int, discussion string, opt *gitlab.AddMergeRequestDiscussionNoteOptions, options ...gitlab.RequestOptionFunc) (*gitlab.Note, *gitlab.Response, error) {
	return &gitlab.Note{}, makeResponse(http.StatusOK), nil
}

func addMergeRequestDiscussionNoteErr(pid interface{}, mergeRequest int, discussion string, opt *gitlab.AddMergeRequestDiscussionNoteOptions, options ...gitlab.RequestOptionFunc) (*gitlab.Note, *gitlab.Response, error) {
	return nil, nil, errors.New("Some error from Gitlab")
}

func addMergeRequestDiscussionNoteNon200(pid interface{}, mergeRequest int, discussion string, opt *gitlab.AddMergeRequestDiscussionNoteOptions, options ...gitlab.RequestOptionFunc) (*gitlab.Note, *gitlab.Response, error) {
	return nil, makeResponse(http.StatusSeeOther), nil
}

func TestReplyHandler(t *testing.T) {
	t.Run("Sends a reply", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/reply", ReplyRequest{})
		server := createServer(fakeClient{addMergeRequestDiscussionNote: addMergeRequestDiscussionNote}, &ProjectInfo{}, MockAttachmentReader{})
		data := serveRequest(t, server, request, ReplyResponse{})
		assert(t, data.SuccessResponse.Message, "Replied to comment")
		assert(t, data.SuccessResponse.Status, http.StatusOK)
	})

	t.Run("Disallows non-POST methods", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/reply", ReplyRequest{})
		server := createServer(fakeClient{addMergeRequestDiscussionNote: addMergeRequestDiscussionNote}, &ProjectInfo{}, MockAttachmentReader{})
		data := serveRequest(t, server, request, ErrorResponse{})
		checkBadMethod(t, *data, http.MethodPost)
	})

	t.Run("Handles errors from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/reply", ReplyRequest{})
		server := createServer(fakeClient{addMergeRequestDiscussionNote: addMergeRequestDiscussionNoteErr}, &ProjectInfo{}, MockAttachmentReader{})
		data := serveRequest(t, server, request, ErrorResponse{})
		checkErrorFromGitlab(t, *data, "Could not leave reply")
	})

	t.Run("Handles non-200s from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/reply", ReplyRequest{})
		server := createServer(fakeClient{addMergeRequestDiscussionNote: addMergeRequestDiscussionNoteNon200}, &ProjectInfo{}, MockAttachmentReader{})
		data := serveRequest(t, server, request, ErrorResponse{})
		checkNon200(t, *data, "Could not leave reply", "/reply")
	})
}
