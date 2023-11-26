package main

import (
	"bytes"
	"encoding/json"
	"net/http"
	"testing"
)

func TestDiscussionResolveHandler(t *testing.T) {
	t.Run("Should resolve a discussion", func(t *testing.T) {
		body := DiscussionResolveRequest{
			DiscussionID: "123",
			Resolved:     true,
		}

		j, err := json.Marshal(body)
		if err != nil {
			t.Fatal(err)
		}

		reader := bytes.NewReader(j)

		request := makeRequest(t, http.MethodPut, "/discussions/resolve", reader)
		client := FakeHandlerClient{}
		data := serveRequest(t, DiscussionResolveHandler, client, request, SuccessResponse{})

		assert(t, data.Message, "Discussion resolved")
		assert(t, data.Status, http.StatusOK)
	})

	t.Run("Should mark a discussion unresolved", func(t *testing.T) {
		body := DiscussionResolveRequest{
			DiscussionID: "123",
			Resolved:     false,
		}

		j, err := json.Marshal(body)
		if err != nil {
			t.Fatal(err)
		}

		reader := bytes.NewReader(j)

		request := makeRequest(t, http.MethodPut, "/discussions/resolve", reader)
		client := FakeHandlerClient{}
		data := serveRequest(t, DiscussionResolveHandler, client, request, SuccessResponse{})

		assert(t, data.Message, "Discussion unresolved")
		assert(t, data.Status, http.StatusOK)
	})

	t.Run("Disallows non-PUT method", func(t *testing.T) {
		body := DiscussionResolveRequest{
			DiscussionID: "123",
			Resolved:     true,
		}

		j, err := json.Marshal(body)
		if err != nil {
			t.Fatal(err)
		}

		reader := bytes.NewReader(j)

		request := makeRequest(t, http.MethodPut, "/discussions/resolve", reader)
		client := FakeHandlerClient{}
		data := serveRequest(t, DiscussionResolveHandler, client, request, ErrorResponse{})

		assert(t, data.Status, http.StatusMethodNotAllowed)
		assert(t, data.Details, "Invalid request type")
		assert(t, data.Message, "Expected PUT")
	})

	t.Run("Handles errors from Gitlab client", func(t *testing.T) {
		body := DiscussionResolveRequest{
			DiscussionID: "123",
			Resolved:     true,
		}

		j, err := json.Marshal(body)
		if err != nil {
			t.Fatal(err)
		}

		reader := bytes.NewReader(j)

		request := makeRequest(t, http.MethodPut, "/discussions/resolve", reader)
		client := FakeHandlerClient{Error: "Some error from Gitlab"}
		data := serveRequest(t, DiscussionResolveHandler, client, request, ErrorResponse{})

		assert(t, data.Status, http.StatusInternalServerError)
		assert(t, data.Message, "Could not resolve discussion")
		assert(t, data.Details, "Some error from Gitlab")
	})

	t.Run("Handles non-200s from Gitlab client", func(t *testing.T) {

		body := DiscussionResolveRequest{
			DiscussionID: "123",
			Resolved:     false,
		}

		j, err := json.Marshal(body)
		if err != nil {
			t.Fatal(err)
		}

		reader := bytes.NewReader(j)

		request := makeRequest(t, http.MethodPut, "/discussions/resolve", reader)
		client := FakeHandlerClient{StatusCode: http.StatusSeeOther}
		data := serveRequest(t, DiscussionResolveHandler, client, request, ErrorResponse{})

		assert(t, data.Status, http.StatusSeeOther)
		assert(t, data.Message, "Gitlab returned non-200 status")
		assert(t, data.Details, "An error occurred on the /discussions/resolve endpoint")
	})
}
