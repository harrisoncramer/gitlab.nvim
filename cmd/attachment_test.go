package main

import (
	"bytes"
	"context"
	"encoding/json"
	"testing"
)

type MockFileReader struct{}

func (mf *MockFileReader) Read(p []byte) (n int, err error) {
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
		request := makeRequest(t, "POST", "/mr/attachment", reader)
		ctx := context.WithValue(context.Background(), "fileReader", mockFileReader)
		rwq := request.WithContext(ctx)

		client := FakeHandlerClient{}
		var data AttachmentResponse

		data = serveRequest(t, AttachmentHandler, client, rwq, data)
		assert(t, data.SuccessResponse.Status, 200)
		assert(t, data.SuccessResponse.Message, "File uploaded successfully")
		assert(t, data.Markdown, "Some markdown data")
		assert(t, data.Alt, "Some alt text")
	})

	// t.Run("Disallows non-GET method", func(t *testing.T) {
	// 	request := makeRequest(t, "POST", "/info", nil)
	// 	client := FakeHandlerClient{}
	// 	var data ErrorResponse
	// 	data = serveRequest(t, InfoHandler, client, request, data)
	// 	assert(t, data.Status, 405)
	// 	assert(t, data.Message, "That request type is not allowed")
	// })
	//
	// t.Run("Handles errors from Gitlab client", func(t *testing.T) {
	// 	request := makeRequest(t, "GET", "/info", nil)
	// 	client := FakeHandlerClient{Error: "Some error from Gitlab"}
	// 	var data ErrorResponse
	// 	data = serveRequest(t, InfoHandler, client, request, data)
	// 	assert(t, data.Status, 500)
	// 	assert(t, data.Message, "Could not get project info and initialize gitlab.nvim plugin")
	// 	assert(t, data.Details, "Some error from Gitlab")
	// })
	//
	// t.Run("Handles non-200s from Gitlab client", func(t *testing.T) {
	// 	request := makeRequest(t, "GET", "/info", nil)
	// 	client := FakeHandlerClient{StatusCode: 302}
	// 	var data ErrorResponse
	// 	data = serveRequest(t, InfoHandler, client, request, data)
	// 	assert(t, data.Status, 302)
	// 	assert(t, data.Message, "Gitlab returned non-200 status")
	// 	assert(t, data.Details, "An error occured on the /info endpoint")
	// })
}
