package main

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"testing"
)

type MockFileReader struct{}

func (mf MockFileReader) Read(p []byte) (n int, err error) {
	return 0, nil
}

func TestAttachmentHandler(t *testing.T) {
	t.Run("Returns 200-status response after upload", func(t *testing.T) {

		body := AttachmentRequest{
			FilePath: "some_file_path",
			FileName: "some_file_name",
		}

		b, err := json.Marshal(body)
		if err != nil {
			t.Fatal(err)
		}

		mockFileReader := MockFileReader{}
		reader := bytes.NewReader(b)
		request := makeRequest(t, http.MethodPost, "/mr/attachment", reader)
		ctx := context.WithValue(context.Background(), fileReaderKey, mockFileReader)
		rwq := request.WithContext(ctx)

		client := FakeHandlerClient{}
		data := serveRequest(t, AttachmentHandler, client, rwq, AttachmentResponse{})
		assert(t, data.SuccessResponse.Status, http.StatusOK)
		assert(t, data.SuccessResponse.Message, "File uploaded successfully")
	})

	t.Run("Disallows non-POST method", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/info", nil)
		client := FakeHandlerClient{}
		data := serveRequest(t, AttachmentHandler, client, request, ErrorResponse{})
		assert(t, data.Status, http.StatusMethodNotAllowed)
		assert(t, data.Details, "Invalid request type")
		assert(t, data.Message, "Expected POST")
	})

	t.Run("Handles errors from Gitlab client", func(t *testing.T) {
		body := AttachmentRequest{
			FilePath: "some_file_path",
			FileName: "some_file_name",
		}

		b, err := json.Marshal(body)
		if err != nil {
			t.Fatal(err)
		}

		mockFileReader := MockFileReader{}
		reader := bytes.NewReader(b)
		request := makeRequest(t, http.MethodPost, "/mr/attachment", reader)
		ctx := context.WithValue(context.Background(), fileReaderKey, mockFileReader)
		rwq := request.WithContext(ctx)
		client := FakeHandlerClient{Error: "Some error from Gitlab"}
		data := serveRequest(t, AttachmentHandler, client, rwq, ErrorResponse{})

		assert(t, data.Status, http.StatusInternalServerError)
		assert(t, data.Message, "Could not upload some_file_name to Gitlab")
		assert(t, data.Details, "Some error from Gitlab")
	})

	t.Run("Handles non-200s from Gitlab client", func(t *testing.T) {
		body := AttachmentRequest{
			FilePath: "some_file_path",
			FileName: "some_file_name",
		}

		b, err := json.Marshal(body)
		if err != nil {
			t.Fatal(err)
		}

		mockFileReader := MockFileReader{}
		reader := bytes.NewReader(b)
		request := makeRequest(t, http.MethodPost, "/mr/attachment", reader)
		ctx := context.WithValue(context.Background(), fileReaderKey, mockFileReader)
		rwq := request.WithContext(ctx)
		client := FakeHandlerClient{StatusCode: http.StatusSeeOther}
		data := serveRequest(t, AttachmentHandler, client, rwq, ErrorResponse{})

		assert(t, data.Status, http.StatusSeeOther)
		assert(t, data.Message, "Gitlab returned non-200 status")
		assert(t, data.Details, "An error occurred on the /mr/attachment endpoint")
	})
}
