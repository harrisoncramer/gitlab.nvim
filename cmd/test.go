package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/xanzy/go-gitlab"
)

/*
The FakeHandlerClient is used to create a fake gitlab client for testing our handlers, where the gitlab APIs are all mocked depending on what is provided during the variable initialization, so that we can simulate different responses from Gitlab
*/
type FakeHandlerClient struct {
	Title       string
	Description string
	StatusCode  int
	Error       string
}

func (f FakeHandlerClient) GetMergeRequest(pid interface{}, mergeRequest int, opt *gitlab.GetMergeRequestsOptions, options ...gitlab.RequestOptionFunc) (*gitlab.MergeRequest, *gitlab.Response, error) {
	if f.Error != "" {
		return nil, nil, errors.New(f.Error)
	}
	return &gitlab.MergeRequest{
		Title:       f.Title,
		Description: f.Description,
	}, makeResponse(f), nil
}

func (f FakeHandlerClient) UpdateMergeRequest(pid interface{}, mergeRequest int, opt *gitlab.UpdateMergeRequestOptions, options ...gitlab.RequestOptionFunc) (*gitlab.MergeRequest, *gitlab.Response, error) {
	if f.Error != "" {
		return nil, nil, errors.New(f.Error)
	}
	return &gitlab.MergeRequest{
		Title:       f.Title,
		Description: f.Description,
	}, makeResponse(f), nil
}

func (f FakeHandlerClient) UploadFile(pid interface{}, content io.Reader, filename string, options ...gitlab.RequestOptionFunc) (*gitlab.ProjectFile, *gitlab.Response, error) {
	return &gitlab.ProjectFile{}, makeResponse(f), nil
}

func (f FakeHandlerClient) GetMergeRequestDiffVersions(pid interface{}, mergeRequest int, opt *gitlab.GetMergeRequestDiffVersionsOptions, options ...gitlab.RequestOptionFunc) ([]*gitlab.MergeRequestDiffVersion, *gitlab.Response, error) {
	return []*gitlab.MergeRequestDiffVersion{}, makeResponse(f), nil
}

func (f FakeHandlerClient) ApproveMergeRequest(pid interface{}, mr int, opt *gitlab.ApproveMergeRequestOptions, options ...gitlab.RequestOptionFunc) (*gitlab.MergeRequestApprovals, *gitlab.Response, error) {
	return &gitlab.MergeRequestApprovals{}, &gitlab.Response{}, nil
}

func (f FakeHandlerClient) UnapproveMergeRequest(pid interface{}, mr int, options ...gitlab.RequestOptionFunc) (*gitlab.Response, error) {
	return &gitlab.Response{}, nil
}

func (f FakeHandlerClient) ListMergeRequestDiscussions(pid interface{}, mergeRequest int, opt *gitlab.ListMergeRequestDiscussionsOptions, options ...gitlab.RequestOptionFunc) ([]*gitlab.Discussion, *gitlab.Response, error) {
	return []*gitlab.Discussion{}, &gitlab.Response{}, nil
}

func (f FakeHandlerClient) ResolveMergeRequestDiscussion(pid interface{}, mergeRequest int, discussion string, opt *gitlab.ResolveMergeRequestDiscussionOptions, options ...gitlab.RequestOptionFunc) (*gitlab.Discussion, *gitlab.Response, error) {
	return &gitlab.Discussion{}, &gitlab.Response{}, nil
}

func (f FakeHandlerClient) CreateMergeRequestDiscussion(pid interface{}, mergeRequest int, opt *gitlab.CreateMergeRequestDiscussionOptions, options ...gitlab.RequestOptionFunc) (*gitlab.Discussion, *gitlab.Response, error) {
	return &gitlab.Discussion{}, &gitlab.Response{}, nil
}

func (f FakeHandlerClient) UpdateMergeRequestDiscussionNote(pid interface{}, mergeRequest int, discussion string, note int, opt *gitlab.UpdateMergeRequestDiscussionNoteOptions, options ...gitlab.RequestOptionFunc) (*gitlab.Note, *gitlab.Response, error) {
	return &gitlab.Note{}, &gitlab.Response{}, nil
}

func (f FakeHandlerClient) DeleteMergeRequestDiscussionNote(pid interface{}, mergeRequest int, discussion string, note int, options ...gitlab.RequestOptionFunc) (*gitlab.Response, error) {
	return &gitlab.Response{}, nil
}

func (f FakeHandlerClient) AddMergeRequestDiscussionNote(pid interface{}, mergeRequest int, discussion string, opt *gitlab.AddMergeRequestDiscussionNoteOptions, options ...gitlab.RequestOptionFunc) (*gitlab.Note, *gitlab.Response, error) {
	return &gitlab.Note{}, &gitlab.Response{}, nil
}

func (f FakeHandlerClient) ListAllProjectMembers(pid interface{}, opt *gitlab.ListProjectMembersOptions, options ...gitlab.RequestOptionFunc) ([]*gitlab.ProjectMember, *gitlab.Response, error) {
	return []*gitlab.ProjectMember{}, &gitlab.Response{}, nil
}

func (f FakeHandlerClient) RetryPipelineBuild(pid interface{}, pipeline int, options ...gitlab.RequestOptionFunc) (*gitlab.Pipeline, *gitlab.Response, error) {
	return &gitlab.Pipeline{}, &gitlab.Response{}, nil
}

func (f FakeHandlerClient) ListPipelineJobs(pid interface{}, pipelineID int, opts *gitlab.ListJobsOptions, options ...gitlab.RequestOptionFunc) ([]*gitlab.Job, *gitlab.Response, error) {
	return []*gitlab.Job{}, &gitlab.Response{}, nil
}

func (f FakeHandlerClient) GetTraceFile(pid interface{}, jobID int, options ...gitlab.RequestOptionFunc) (*bytes.Reader, *gitlab.Response, error) {
	return &bytes.Reader{}, &gitlab.Response{}, nil
}

/* The assert function is a helper function used to check two comparables */
func assert[T comparable](t *testing.T, got T, want T) {
	t.Helper()
	if got != want {
		t.Errorf("Got %v but wanted %v", got, want)
	}
}

/* The assertNot function is a helper function used to check that two comparables are NOT equal */
func assertNot[T comparable](t *testing.T, got T, want T) {
	t.Helper()
	if got == want {
		t.Errorf("Got %v but wanted %v", got, want)
	}
}

/* Will create a new request with the given method, endpoint and body */
func makeRequest(t *testing.T, method string, endpoint string, body io.Reader) *http.Request {
	request, err := http.NewRequest(method, endpoint, body)
	if err != nil {
		t.Fatal(err)
	}

	return request
}

/* Will serve and parse the JSON from an endpoint into the given type */
func serveRequest[T interface{}](t *testing.T, h handlerFunc, client FakeHandlerClient, request *http.Request, target T) T {
	recorder := httptest.NewRecorder()
	projectInfo := ProjectInfo{}
	handler := http.HandlerFunc(Middleware(client, &projectInfo, h))
	handler.ServeHTTP(recorder, request)
	result := recorder.Result()
	decoder := json.NewDecoder(result.Body)
	err := decoder.Decode(&target)
	if err != nil {
		t.Fatalf("Failed to read JSON: %v", err)
	}

	return target
}

/* Make response makes a simple response value with the right status code */
func makeResponse(f FakeHandlerClient) *gitlab.Response {

	if f.StatusCode == 0 {
		f.StatusCode = 200
	}
	return &gitlab.Response{
		Response: &http.Response{
			StatusCode: f.StatusCode,
		},
	}
}
