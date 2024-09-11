package app

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/xanzy/go-gitlab"
)

type fakeTraceFileGetter struct {
	testBase
}

func getTraceFileData(t *testing.T, svc http.Handler, request *http.Request) JobTraceResponse {
	res := httptest.NewRecorder()
	svc.ServeHTTP(res, request)

	var data JobTraceResponse
	err := json.Unmarshal(res.Body.Bytes(), &data)
	if err != nil {
		t.Error(err)
	}
	return data
}

func (f fakeTraceFileGetter) GetTraceFile(pid interface{}, jobID int, options ...gitlab.RequestOptionFunc) (*bytes.Reader, *gitlab.Response, error) {
	resp, err := f.handleGitlabError()
	if err != nil {
		return nil, nil, err
	}
	re := bytes.NewReader([]byte("Some data"))
	return re, resp, err
}

// var jobId = 0
func TestJobHandler(t *testing.T) {
	t.Run("Should read a job trace file", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/job", JobTraceRequest{})
		client := fakeTraceFileGetter{}
		svc := traceFileService{testProjectData, client}
		data := getTraceFileData(t, svc, request)
		assert(t, data.Message, "Log file read")
		assert(t, data.File, "Some data")
	})
	t.Run("Handles errors from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/job", JobTraceRequest{})
		client := fakeTraceFileGetter{testBase{errFromGitlab: true}}
		svc := traceFileService{testProjectData, client}
		data := getFailData(t, svc, request)
		checkErrorFromGitlab(t, data, "Could not get trace file for job")
	})

	t.Run("Handles non-200s from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/job", JobTraceRequest{})
		client := fakeTraceFileGetter{testBase{status: http.StatusSeeOther}}
		svc := traceFileService{testProjectData, client}
		data := getFailData(t, svc, request)
		checkNon200(t, data, "Could not get trace file for job", "/job")
	})
}
