package main

import (
	"bytes"
	"encoding/json"
	"net/http"
	"strings"
	"testing"
)

func TestSummaryHandler(t *testing.T) {
	t.Run("Returns 200 after successful PUT to summary", func(t *testing.T) {
		body, err := json.Marshal(SummaryUpdateRequest{
			Title:       "Some title",
			Description: "Some description",
		})
		if err != nil {
			t.Fatal(err)
		}

		reader := bytes.NewReader(body)
		request := makeRequest(t, http.MethodPut, "/mr/summary", reader)

		client := FakeHandlerClient{}
		data := serveRequest(t, SummaryHandler, client, request, SummaryUpdateResponse{})
		assert(t, data.SuccessResponse.Message, "Summary updated")
		assert(t, data.SuccessResponse.Status, http.StatusOK)
	})

	t.Run("Disallows non-PUT methods", func(t *testing.T) {
		body := strings.NewReader("")
		request := makeRequest(t, http.MethodPost, "/info", body)
		client := FakeHandlerClient{}
		data := serveRequest(t, SummaryHandler, client, request, ErrorResponse{})
		assert(t, data.Status, http.StatusMethodNotAllowed)
		assert(t, data.Details, "Invalid request type")
		assert(t, data.Message, "Expected PUT")
	})

	t.Run("Handles errors from Gitlab client", func(t *testing.T) {
		body, err := json.Marshal(SummaryUpdateRequest{
			Title:       "Some title",
			Description: "Some description",
		})
		if err != nil {
			t.Fatal(err)
		}
		reader := bytes.NewReader(body)
		request := makeRequest(t, http.MethodPut, "/mr/summary", reader)
		client := FakeHandlerClient{Error: "Some error from Gitlab"}
		data := serveRequest(t, SummaryHandler, client, request, ErrorResponse{})
		assert(t, data.Status, http.StatusInternalServerError)
		assert(t, data.Message, "Could not edit merge request summary")
		assert(t, data.Details, "Some error from Gitlab")
	})

	t.Run("Handles non-200s from Gitlab client", func(t *testing.T) {
		body, err := json.Marshal(SummaryUpdateRequest{
			Title:       "Some title",
			Description: "Some description",
		})
		if err != nil {
			t.Fatal(err)
		}
		reader := bytes.NewReader(body)
		request := makeRequest(t, http.MethodPut, "/mr/summary", reader)
		client := FakeHandlerClient{StatusCode: http.StatusSeeOther}
		data := serveRequest(t, SummaryHandler, client, request, ErrorResponse{})
		assert(t, data.Status, http.StatusSeeOther)
		assert(t, data.Message, "Gitlab returned non-200 status")
		assert(t, data.Details, "An error occurred on the /summary endpoint")
	})
}
