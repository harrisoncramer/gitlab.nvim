package main

import (
	"bytes"
	"encoding/json"
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
		request := makeRequest(t, "PUT", "/mr/summary", reader)

		client := FakeHandlerClient{}
		var data SummaryUpdateResponse
		data = serveRequest(t, SummaryHandler, client, request, data)
		assert(t, data.SuccessResponse.Message, "Summary updated")
		assert(t, data.SuccessResponse.Status, 200)
	})

	t.Run("Disallows non-PUT methods", func(t *testing.T) {
		body := strings.NewReader("")
		request := makeRequest(t, "POST", "/info", body)
		client := FakeHandlerClient{}
		var data ErrorResponse
		data = serveRequest(t, SummaryHandler, client, request, data)
		assert(t, data.Status, 405)
		assert(t, data.Message, "That request type is not allowed")
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
		request := makeRequest(t, "PUT", "/mr/summary", reader)
		client := FakeHandlerClient{Error: "Some error from Gitlab"}
		var data ErrorResponse
		data = serveRequest(t, SummaryHandler, client, request, data)
		assert(t, data.Status, 500)
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
		request := makeRequest(t, "PUT", "/mr/summary", reader)
		client := FakeHandlerClient{StatusCode: 302}
		var data ErrorResponse
		data = serveRequest(t, SummaryHandler, client, request, data)
		assert(t, data.Status, 302)
		assert(t, data.Message, "Gitlab returned non-200 status")
		assert(t, data.Details, "An error occured on the /summary endpoint")
	})
}
