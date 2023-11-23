package main

import (
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestInfoHandler(t *testing.T) {
	t.Run("Returns normal information", func(t *testing.T) {
		request := makeRequest(t, "GET", "/info", nil)
		client := FakeHandlerClient{
			Title: "Some Title",
		}

		var data InfoResponse
		decoder := serveRequest(t, client, request)
		err := decoder.Decode(&data)
		if err != nil {
			t.Fatalf("Failed to read JSON: %v", err)
		}

		assert(t, data.Info.Title, client.Title)
		assert(t, data.SuccessResponse.Message, "Merge requests retrieved")
		assert(t, data.SuccessResponse.Status, 200)
	})

	t.Run("Disallows non-GET method", func(t *testing.T) {
		request := makeRequest(t, "POST", "/info", nil)
		client := FakeHandlerClient{}

		var data ErrorResponse
		decoder := serveRequest(t, client, request)
		err := decoder.Decode(&data)
		if err != nil {
			t.Fatalf("Failed to read JSON: %v", err)
		}

		assert(t, data.Status, 405)
		assert(t, data.Message, "That request type is not allowed")
	})

	t.Run("Handles errors from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, "GET", "/info", nil)
		client := FakeHandlerClient{
			Error: "Some error from Gitlab",
		}

		var data ErrorResponse
		decoder := serveRequest(t, client, request)
		err := decoder.Decode(&data)
		if err != nil {
			t.Fatalf("Failed to read JSON: %v", err)
		}

		assert(t, data.Status, 500)
		assert(t, data.Message, "Could not get project info and initialize gitlab.nvim plugin")
		assert(t, data.Details, "Some error from Gitlab")
	})

	t.Run("Handles non-200s from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, "GET", "/info", nil)
		client := FakeHandlerClient{
			StatusCode: 302,
		}

		var data ErrorResponse
		decoder := serveRequest(t, client, request)
		err := decoder.Decode(&data)
		if err != nil {
			t.Fatalf("Failed to read JSON: %v", err)
		}

		assert(t, data.Status, 302)
		assert(t, data.Message, "Gitlab returned non-200 status")
		assert(t, data.Details, "An error occured on the /info endpoint")
	})
}

func assert[T comparable](t *testing.T, got T, want T) {
	t.Helper()
	if got != want {
		t.Errorf("Got %v but wanted %v", got, want)
	}
}

func makeRequest(t *testing.T, method string, endpoint string, body io.Reader) *http.Request {
	request, err := http.NewRequest(method, endpoint, body)
	if err != nil {
		t.Fatal(err)
	}

	return request
}

func serveRequest(t *testing.T, client FakeHandlerClient, request *http.Request) *json.Decoder {
	recorder := httptest.NewRecorder()
	projectInfo := ProjectInfo{}
	handler := http.HandlerFunc(Middleware(client, &projectInfo, InfoHandler))
	handler.ServeHTTP(recorder, request)
	result := recorder.Result()
	decoder := json.NewDecoder(result.Body)
	return decoder
}
