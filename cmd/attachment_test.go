package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"testing"

	"github.com/xanzy/go-gitlab"
)

type MockAttachmentReader struct{}

func (mf MockAttachmentReader) ReadFile(path string) (io.Reader, error) {
	return bytes.NewReader([]byte{}), nil
}

func uploadFile(pid interface{}, content io.Reader, filename string, options ...gitlab.RequestOptionFunc) (*gitlab.ProjectFile, *gitlab.Response, error) {
	return &gitlab.ProjectFile{}, makeResponse(http.StatusOK), nil
}

func uploadFileNon200(pid interface{}, content io.Reader, filename string, options ...gitlab.RequestOptionFunc) (*gitlab.ProjectFile, *gitlab.Response, error) {
	return &gitlab.ProjectFile{}, makeResponse(http.StatusSeeOther), nil
}

func uploadFileErr(pid interface{}, content io.Reader, filename string, options ...gitlab.RequestOptionFunc) (*gitlab.ProjectFile, *gitlab.Response, error) {
	return nil, nil, errors.New("Some error from Gitlab")
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

		reader := bytes.NewReader(b)
		request := makeRequest(t, http.MethodPost, "/mr/attachment", reader)
		server := createServer(fakeClient{uploadFile: uploadFile}, &ProjectInfo{}, MockAttachmentReader{})
		data, err := serveRequest(server, request, InfoResponse{})

		assert(t, data.SuccessResponse.Status, http.StatusOK)
		assert(t, data.SuccessResponse.Message, "File uploaded successfully")
	})

	t.Run("Disallows non-POST method", func(t *testing.T) {
		body := AttachmentRequest{
			FilePath: "some_file_path",
			FileName: "some_file_name",
		}

		b, err := json.Marshal(body)
		if err != nil {
			t.Fatal(err)
		}

		reader := bytes.NewReader(b)
		request := makeRequest(t, http.MethodPut, "/mr/attachment", reader)
		server := createServer(fakeClient{uploadFile: uploadFile}, &ProjectInfo{}, MockAttachmentReader{})
		data, err := serveRequest(server, request, ErrorResponse{})
		if err != nil {
			t.Fatal(err)
		}
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

		reader := bytes.NewReader(b)
		request := makeRequest(t, http.MethodPost, "/mr/attachment", reader)
		server := createServer(fakeClient{uploadFile: uploadFileErr}, &ProjectInfo{}, MockAttachmentReader{})
		data, err := serveRequest(server, request, ErrorResponse{})
		if err != nil {
			t.Fatal(err)
		}

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

		reader := bytes.NewReader(b)
		request := makeRequest(t, http.MethodPost, "/mr/attachment", reader)
		server := createServer(fakeClient{uploadFile: uploadFileNon200}, &ProjectInfo{}, MockAttachmentReader{})
		data, err := serveRequest(server, request, ErrorResponse{})
		if err != nil {
			t.Fatal(err)
		}

		assert(t, data.Status, http.StatusSeeOther)
		assert(t, data.Message, "Could not upload some_file_name to Gitlab")
		assert(t, data.Details, "An error occurred on the /mr/attachment endpoint")
	})
}
