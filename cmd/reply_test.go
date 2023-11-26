package main

import (
	"bytes"
	"encoding/json"
	"net/http"
	"testing"
)

func TestReplyHandler(t *testing.T) {
	t.Run("Replies to comment", func(t *testing.T) {
		body := ReplyRequest{}
		b, err := json.Marshal(body)
		if err != nil {
			t.Fatal(err)
		}

		reader := bytes.NewReader(b)
		request := makeRequest(t, http.MethodPost, "/reply", reader)
		client := FakeHandlerClient{}
		data := serveRequest(t, ReplyHandler, client, request, SuccessResponse{})
		assert(t, data.Message, "Replied to comment")
		assert(t, data.Status, http.StatusOK)
	})

	t.Run("Disallows non-POST method", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/reply", nil)
		client := FakeHandlerClient{}
		data := serveRequest(t, ReplyHandler, client, request, ErrorResponse{})
		assert(t, data.Status, http.StatusMethodNotAllowed)
		assert(t, data.Details, "Invalid request type")
		assert(t, data.Message, "Expected POST")
	})

	t.Run("Handles errors from Gitlab client", func(t *testing.T) {
		body := ReplyRequest{}
		b, err := json.Marshal(body)
		if err != nil {
			t.Fatal(err)
		}

		reader := bytes.NewReader(b)
		request := makeRequest(t, http.MethodPost, "/reply", reader)
		client := FakeHandlerClient{Error: "Some error from Gitlab"}
		data := serveRequest(t, ReplyHandler, client, request, ErrorResponse{})
		assert(t, data.Status, http.StatusInternalServerError)
		assert(t, data.Message, "Could not leave reply")
		assert(t, data.Details, "Some error from Gitlab")
	})

	t.Run("Handles non-200s from Gitlab client", func(t *testing.T) {
		body := ReplyRequest{}
		b, err := json.Marshal(body)
		if err != nil {
			t.Fatal(err)
		}

		reader := bytes.NewReader(b)
		request := makeRequest(t, http.MethodPost, "/reply", reader)
		client := FakeHandlerClient{StatusCode: http.StatusSeeOther}
		data := serveRequest(t, ReplyHandler, client, request, ErrorResponse{})
		assert(t, data.Status, http.StatusSeeOther)
		assert(t, data.Message, "Could not leave reply")
		assert(t, data.Details, "An error occurred on the /reply endpoint")
	})
}
