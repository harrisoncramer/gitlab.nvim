package main

import (
	"bytes"
	"encoding/json"
	"net/http"
	"testing"
)

func TestDeleteComment(t *testing.T) {
	t.Run("Should delete a comment", func(t *testing.T) {
		b, err := json.Marshal(DeleteCommentRequest{})
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
		b, err := json.Marshal(DeleteCommentRequest{})
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
		assert(t, data.Message, "Could not delete comment")
		assert(t, data.Details, "An error occurred on the /comment endpoint")
	})
}

func TestEditComment(t *testing.T) {
	t.Run("Should edit a comment", func(t *testing.T) {
		b, err := json.Marshal(EditCommentRequest{})
		if err != nil {
			t.Fatal(err)
		}

		body := bytes.NewReader(b)
		request := makeRequest(t, http.MethodPatch, "/comment", body)
		client := FakeHandlerClient{}
		data := serveRequest(t, CommentHandler, client, request, SuccessResponse{})
		assert(t, data.Message, "Comment updated successfully")
		assert(t, data.Status, http.StatusOK)
	})

	t.Run("Edit handles errors from Gitlab client", func(t *testing.T) {
		b, err := json.Marshal(EditCommentRequest{})
		if err != nil {
			t.Fatal(err)
		}

		body := bytes.NewReader(b)
		request := makeRequest(t, http.MethodPatch, "/comment", body)
		client := FakeHandlerClient{Error: "Some error from Gitlab"}
		data := serveRequest(t, CommentHandler, client, request, ErrorResponse{})
		assert(t, data.Message, "Could not update comment")
		assert(t, data.Details, "Some error from Gitlab")
	})

	t.Run("Edit handles non-200s from Gitlab client", func(t *testing.T) {
		b, err := json.Marshal(EditCommentRequest{
			Comment:      "Hi there",
			NoteId:       1,
			DiscussionId: "2",
			Resolved:     false,
		})
		if err != nil {
			t.Fatal(err)
		}

		body := bytes.NewReader(b)
		request := makeRequest(t, http.MethodPatch, "/comment", body)
		client := FakeHandlerClient{StatusCode: http.StatusSeeOther}
		data := serveRequest(t, CommentHandler, client, request, ErrorResponse{})
		assert(t, data.Message, "Could not update comment")
		assert(t, data.Details, "An error occurred on the /comment endpoint")
	})
}

func TestPostComment(t *testing.T) {
	t.Run("Should create new comment thread", func(t *testing.T) {
		b, err := json.Marshal(PostCommentRequest{})
		if err != nil {
			t.Fatal(err)
		}

		body := bytes.NewReader(b)
		request := makeRequest(t, http.MethodPost, "/comment", body)
		client := FakeHandlerClient{}
		data := serveRequest(t, CommentHandler, client, request, CommentResponse{})
		assert(t, data.Message, "Comment created successfully")
		assert(t, data.Status, http.StatusOK)
	})
	t.Run("Edit handles errors from Gitlab client", func(t *testing.T) {
		b, err := json.Marshal(PostCommentRequest{})
		if err != nil {
			t.Fatal(err)
		}

		body := bytes.NewReader(b)
		request := makeRequest(t, http.MethodPost, "/comment", body)
		client := FakeHandlerClient{Error: "Some error from Gitlab"}
		data := serveRequest(t, CommentHandler, client, request, ErrorResponse{})
		assert(t, data.Message, "Could not create comment")
		assert(t, data.Details, "Some error from Gitlab")
	})

	t.Run("Edit handles non-200s from Gitlab client", func(t *testing.T) {
		b, err := json.Marshal(PostCommentRequest{})
		if err != nil {
			t.Fatal(err)
		}

		body := bytes.NewReader(b)
		request := makeRequest(t, http.MethodPost, "/comment", body)
		client := FakeHandlerClient{StatusCode: http.StatusSeeOther}
		data := serveRequest(t, CommentHandler, client, request, ErrorResponse{})
		assert(t, data.Message, "Could not create comment")
		assert(t, data.Details, "An error occurred on the /comment endpoint")
	})
}
