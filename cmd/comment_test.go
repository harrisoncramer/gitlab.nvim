package main

import (
	"bytes"
	"encoding/json"
	"net/http"
	"testing"
)

func TestCommentHandler(t *testing.T) {
	t.Run("Should delete a comment", func(t *testing.T) {
		b, err := json.Marshal(DeleteCommentRequest{
			NoteId:       1,
			DiscussionId: "2",
		})
		if err != nil {
			t.Fatal(err)
		}

		body := bytes.NewReader(b)
		request := makeRequest(t, http.MethodDelete, "/comment", body)
		client := FakeHandlerClient{}
		data := serveRequest(t, CommentHandler, client, request, SuccessResponse{})
		assert(t, data.Message, "Comment deleted successfully")
		assert(t, data.Status, http.StatusOK)
	})

	t.Run("Delete handles errors from Gitlab client", func(t *testing.T) {
		b, err := json.Marshal(DeleteCommentRequest{
			NoteId:       1,
			DiscussionId: "2",
		})
		if err != nil {
			t.Fatal(err)
		}

		body := bytes.NewReader(b)
		request := makeRequest(t, http.MethodDelete, "/comment", body)
		client := FakeHandlerClient{Error: "Some error from Gitlab"}
		data := serveRequest(t, CommentHandler, client, request, ErrorResponse{})
		assert(t, data.Message, "Could not delete comment")
		assert(t, data.Details, "Some error from Gitlab")
	})

	t.Run("Delete handles non-200s from Gitlab client", func(t *testing.T) {
		b, err := json.Marshal(DeleteCommentRequest{
			NoteId:       1,
			DiscussionId: "2",
		})
		if err != nil {
			t.Fatal(err)
		}

		body := bytes.NewReader(b)
		request := makeRequest(t, http.MethodDelete, "/comment", body)
		client := FakeHandlerClient{StatusCode: http.StatusSeeOther}
		data := serveRequest(t, CommentHandler, client, request, ErrorResponse{})
		assert(t, data.Message, "Gitlab returned non-200 status")
		assert(t, data.Details, "An error occurred on the /comment endpoint")
	})
}
