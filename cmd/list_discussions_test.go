package main

import (
	"bytes"
	"encoding/json"
	"net/http"
	"testing"
)

func TestListDiscussions(t *testing.T) {
	t.Run("Gets list of all discussions sorted newest to oldest", func(t *testing.T) {
		body := DiscussionsRequest{}
		j, err := json.Marshal(body)
		if err != nil {
			t.Fatal(err)
		}
		reader := bytes.NewReader(j)
		request := makeRequest(t, http.MethodPost, "/discussions/list", reader)
		client := FakeHandlerClient{}
		data := serveRequest(t, listDiscussionsHandler, client, request, DiscussionsResponse{})
		assert(t, data.SuccessResponse.Message, "Discussions fetched")
		assert(t, data.SuccessResponse.Status, http.StatusOK)

		first := data.Discussions[0]
		second := data.Discussions[1]
		assert(t, first.Notes[0].Author.Username, "hcramer2")
		assert(t, second.Notes[0].Author.Username, "hcramer")
	})

	t.Run("Disallows non-POST method", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/discussions/list", nil)
		client := FakeHandlerClient{}
		data := serveRequest(t, listDiscussionsHandler, client, request, ErrorResponse{})
		assert(t, data.Status, http.StatusMethodNotAllowed)
		assert(t, data.Details, "Invalid request type")
		assert(t, data.Message, "Expected POST")
	})

	t.Run("Handles errors from Gitlab client", func(t *testing.T) {
		body := DiscussionsRequest{}
		j, err := json.Marshal(body)
		if err != nil {
			t.Fatal(err)
		}
		reader := bytes.NewReader(j)
		request := makeRequest(t, http.MethodPost, "/discussions/list", reader)
		client := FakeHandlerClient{Error: "Some error from Gitlab"}
		data := serveRequest(t, listDiscussionsHandler, client, request, ErrorResponse{})
		assert(t, data.Status, http.StatusInternalServerError)
		assert(t, data.Message, "Could not list discussions")
		assert(t, data.Details, "Some error from Gitlab")
	})

	t.Run("Handles non-200s from Gitlab client", func(t *testing.T) {
		body := DiscussionsRequest{}
		j, err := json.Marshal(body)
		if err != nil {
			t.Fatal(err)
		}
		reader := bytes.NewReader(j)
		request := makeRequest(t, http.MethodPost, "/discussions/list", reader)
		client := FakeHandlerClient{StatusCode: http.StatusSeeOther}
		data := serveRequest(t, listDiscussionsHandler, client, request, ErrorResponse{})
		assert(t, data.Status, http.StatusSeeOther)
		assert(t, data.Message, "Could not list discussions")
		assert(t, data.Details, "An error occurred on the /discussions/list endpoint")
	})
}
