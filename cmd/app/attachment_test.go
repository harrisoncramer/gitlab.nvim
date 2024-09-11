package app

import (
	"bytes"
	"io"
	"net/http"
	"testing"

	"github.com/xanzy/go-gitlab"
)

type fakeFileUploaderClient struct {
	testBase
}

func (f fakeFileUploaderClient) UploadFile(pid interface{}, content io.Reader, filename string, options ...gitlab.RequestOptionFunc) (*gitlab.ProjectFile, *gitlab.Response, error) {
	resp, err := f.handleGitlabError()
	if err != nil {
		return nil, nil, err
	}

	return &gitlab.ProjectFile{}, resp, nil
}

type fakeFileReader struct{}

func (f fakeFileReader) ReadFile(path string) (io.Reader, error) {
	return &bytes.Reader{}, nil
}

func TestAttachmentHandler(t *testing.T) {
	attachmentTestRequestData := AttachmentRequest{
		FileName: "some_file_name",
		FilePath: "some_file_path",
	}

	t.Run("Returns 200-status response after upload", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/attachment", attachmentTestRequestData)
		svc := attachmentService{testProjectData, fakeFileReader{}, fakeFileUploaderClient{}}
		data := getSuccessData(t, svc, request)
		assert(t, data.Message, "File uploaded successfully")
	})

	t.Run("Disallows non-POST method", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/attachment", nil)
		svc := attachmentService{testProjectData, fakeFileReader{}, fakeFileUploaderClient{}}
		data := getFailData(t, svc, request)
		checkBadMethod(t, data, http.MethodPost)
	})
	t.Run("Handles errors from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/attachment", attachmentTestRequestData)
		svc := attachmentService{testProjectData, fakeFileReader{}, fakeFileUploaderClient{testBase{errFromGitlab: true}}}
		data := getFailData(t, svc, request)
		checkErrorFromGitlab(t, data, "Could not upload some_file_name to Gitlab")
	})

	t.Run("Handles non-200s from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/attachment", attachmentTestRequestData)
		svc := attachmentService{testProjectData, fakeFileReader{}, fakeFileUploaderClient{testBase{status: http.StatusSeeOther}}}
		data := getFailData(t, svc, request)
		checkNon200(t, data, "Could not upload some_file_name to Gitlab", "/attachment")
	})
}
