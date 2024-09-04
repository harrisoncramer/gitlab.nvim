package app

import (
	"bytes"
	"net/http"
	"testing"

	"github.com/xanzy/go-gitlab"
	mock_main "gitlab.com/harrisoncramer/gitlab.nvim/cmd/mocks"
)

func withMockFileReader(a *Api) error {
	reader := mock_main.MockAttachmentReader{}
	a.fileReader = reader
	return nil
}

var reader = bytes.NewReader([]byte{})
var attachmentTestRequestData = AttachmentRequest{
	FileName: "some_file_name",
	FilePath: "some_file_path",
}

func TestAttachmentHandler(t *testing.T) {
	t.Run("Returns 200-status response after upload", func(t *testing.T) {
		client := mock_main.NewMockClient(t)
		client.EXPECT().UploadFile("", reader, attachmentTestRequestData.FileName).Return(&gitlab.ProjectFile{}, makeResponse(http.StatusOK), nil)

		request := makeRequest(t, http.MethodPost, "/attachment", attachmentTestRequestData)
		router, _ := CreateRouter(client, withMockFileReader)
		data := serveRequest(t, router, request, AttachmentResponse{})

		assert(t, data.SuccessResponse.Status, http.StatusOK)
		assert(t, data.SuccessResponse.Message, "File uploaded successfully")
	})

	t.Run("Disallows non-POST method", func(t *testing.T) {
		client := mock_main.NewMockClient(t)
		client.EXPECT().UploadFile("", reader, attachmentTestRequestData.FileName).Return(&gitlab.ProjectFile{}, makeResponse(http.StatusOK), nil)

		request := makeRequest(t, http.MethodPut, "/attachment", attachmentTestRequestData)
		router, _ := CreateRouter(client, withMockFileReader)
		data := serveRequest(t, router, request, ErrorResponse{})

		checkBadMethod(t, *data, http.MethodPost)
	})

	t.Run("Handles errors from Gitlab client", func(t *testing.T) {
		client := mock_main.NewMockClient(t)
		client.EXPECT().UploadFile("", reader, attachmentTestRequestData.FileName).Return(nil, nil, errorFromGitlab)

		request := makeRequest(t, http.MethodPost, "/attachment", attachmentTestRequestData)
		router, _ := CreateRouter(client, withMockFileReader)

		data := serveRequest(t, router, request, ErrorResponse{})
		checkErrorFromGitlab(t, *data, "Could not upload some_file_name to Gitlab")
	})

	t.Run("Handles non-200s from Gitlab client", func(t *testing.T) {
		client := mock_main.NewMockClient(t)
		client.EXPECT().UploadFile("", reader, attachmentTestRequestData.FileName).Return(nil, makeResponse(http.StatusSeeOther), nil)

		request := makeRequest(t, http.MethodPost, "/attachment", attachmentTestRequestData)
		router, _ := CreateRouter(client, withMockFileReader)

		data := serveRequest(t, router, request, ErrorResponse{})
		checkNon200(t, *data, "Could not upload some_file_name to Gitlab", "/attachment")
	})
}
