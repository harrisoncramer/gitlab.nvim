package main

import (
	"bytes"
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
		request := makeRequest(t, http.MethodPost, "/mr/attachment", AttachmentRequest{FilePath: "some_file_path", FileName: "some_file_name"})
		server := createServer(fakeClient{uploadFile: uploadFile}, &ProjectInfo{}, MockAttachmentReader{})
		data := serveRequest(t, server, request, AttachmentResponse{})
		assert(t, data.SuccessResponse.Status, http.StatusOK)
		assert(t, data.SuccessResponse.Message, "File uploaded successfully")
	})

	t.Run("Disallows non-POST method", func(t *testing.T) {
		request := makeRequest(t, http.MethodPut, "/mr/attachment", AttachmentRequest{FilePath: "some_file_path", FileName: "some_file_name"})
		server := createServer(fakeClient{uploadFile: uploadFile}, &ProjectInfo{}, MockAttachmentReader{})
		data := serveRequest(t, server, request, ErrorResponse{})
		checkBadMethod(t, *data, http.MethodPost)
	})

	t.Run("Handles errors from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/mr/attachment", AttachmentRequest{FilePath: "some_file_path", FileName: "some_file_name"})
		server := createServer(fakeClient{uploadFile: uploadFileErr}, &ProjectInfo{}, MockAttachmentReader{})
		data := serveRequest(t, server, request, ErrorResponse{})
		checkErrorFromGitlab(t, *data, "Could not upload some_file_name to Gitlab")
	})

	t.Run("Handles non-200s from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/mr/attachment", AttachmentRequest{FilePath: "some_file_path", FileName: "some_file_name"})
		server := createServer(fakeClient{uploadFile: uploadFileNon200}, &ProjectInfo{}, MockAttachmentReader{})
		data := serveRequest(t, server, request, ErrorResponse{})
		checkNon200(t, *data, "Could not upload some_file_name to Gitlab", "/mr/attachment")
	})
}
