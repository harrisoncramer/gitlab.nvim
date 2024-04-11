package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/xanzy/go-gitlab"
)

/*
The FakeHandlerClient is used to create a fake gitlab client for testing our handlers, where the gitlab APIs are all mocked depending on what is provided during the variable initialization, so that we can simulate different responses from Gitlab
*/

type fakeClient struct {
	createMrFn                         func(pid interface{}, opt *gitlab.CreateMergeRequestOptions, options ...gitlab.RequestOptionFunc) (*gitlab.MergeRequest, *gitlab.Response, error)
	getMergeRequestFn                  func(pid interface{}, mergeRequestIID int, opt *gitlab.GetMergeRequestsOptions, options ...gitlab.RequestOptionFunc) (*gitlab.MergeRequest, *gitlab.Response, error)
	updateMergeRequestFn               func(pid interface{}, mergeRequestIID int, opt *gitlab.UpdateMergeRequestOptions, options ...gitlab.RequestOptionFunc) (*gitlab.MergeRequest, *gitlab.Response, error)
	acceptAndMergeFn                   func(pid interface{}, mergeRequestIID int, opt *gitlab.AcceptMergeRequestOptions, options ...gitlab.RequestOptionFunc) (*gitlab.MergeRequest, *gitlab.Response, error)
	unapprorveMergeRequestFn           func(pid interface{}, mergeRequestIID int, options ...gitlab.RequestOptionFunc) (*gitlab.Response, error)
	uploadFile                         func(pid interface{}, content io.Reader, filename string, options ...gitlab.RequestOptionFunc) (*gitlab.ProjectFile, *gitlab.Response, error)
	getMergeRequestDiffVersions        func(pid interface{}, mergeRequestIID int, opt *gitlab.GetMergeRequestDiffVersionsOptions, options ...gitlab.RequestOptionFunc) ([]*gitlab.MergeRequestDiffVersion, *gitlab.Response, error)
	approveMergeRequest                func(pid interface{}, mergeRequestIID int, opt *gitlab.ApproveMergeRequestOptions, options ...gitlab.RequestOptionFunc) (*gitlab.MergeRequestApprovals, *gitlab.Response, error)
	listMergeRequestDiscussions        func(pid interface{}, mergeRequestIID int, opt *gitlab.ListMergeRequestDiscussionsOptions, options ...gitlab.RequestOptionFunc) ([]*gitlab.Discussion, *gitlab.Response, error)
	resolveMergeRequestDiscussion      func(pid interface{}, mergeRequestIID int, discussion string, opt *gitlab.ResolveMergeRequestDiscussionOptions, options ...gitlab.RequestOptionFunc) (*gitlab.Discussion, *gitlab.Response, error)
	createMergeRequestDiscussion       func(pid interface{}, mergeRequestIID int, opt *gitlab.CreateMergeRequestDiscussionOptions, options ...gitlab.RequestOptionFunc) (*gitlab.Discussion, *gitlab.Response, error)
	updateMergeRequestDiscussionNote   func(pid interface{}, mergeRequestIID int, discussion string, note int, opt *gitlab.UpdateMergeRequestDiscussionNoteOptions, options ...gitlab.RequestOptionFunc) (*gitlab.Note, *gitlab.Response, error)
	deleteMergeRequestDiscussionNote   func(pid interface{}, mergeRequestIID int, discussion string, note int, options ...gitlab.RequestOptionFunc) (*gitlab.Response, error)
	addMergeRequestDiscussionNote      func(pid interface{}, mergeRequestIID int, discussion string, opt *gitlab.AddMergeRequestDiscussionNoteOptions, options ...gitlab.RequestOptionFunc) (*gitlab.Note, *gitlab.Response, error)
	listAllProjectMembers              func(pid interface{}, opt *gitlab.ListProjectMembersOptions, options ...gitlab.RequestOptionFunc) ([]*gitlab.ProjectMember, *gitlab.Response, error)
	retryPipelineBuild                 func(pid interface{}, pipeline int, options ...gitlab.RequestOptionFunc) (*gitlab.Pipeline, *gitlab.Response, error)
	listPipelineJobs                   func(pid interface{}, pipelineID int, opts *gitlab.ListJobsOptions, options ...gitlab.RequestOptionFunc) ([]*gitlab.Job, *gitlab.Response, error)
	getLatestPipeline                  func(pid interface{}, opt *gitlab.GetLatestPipelineOptions, options ...gitlab.RequestOptionFunc) (*gitlab.Pipeline, *gitlab.Response, error)
	getTraceFile                       func(pid interface{}, jobID int, options ...gitlab.RequestOptionFunc) (*bytes.Reader, *gitlab.Response, error)
	listLabels                         func(pid interface{}, opt *gitlab.ListLabelsOptions, options ...gitlab.RequestOptionFunc) ([]*gitlab.Label, *gitlab.Response, error)
	listMergeRequestAwardEmojiOnNote   func(pid interface{}, mergeRequestIID, noteID int, opt *gitlab.ListAwardEmojiOptions, options ...gitlab.RequestOptionFunc) ([]*gitlab.AwardEmoji, *gitlab.Response, error)
	deleteMergeRequestAwardEmojiOnNote func(pid interface{}, mergeRequestIID, noteID, awardID int, options ...gitlab.RequestOptionFunc) (*gitlab.Response, error)
	currentUser                        func(options ...gitlab.RequestOptionFunc) (*gitlab.User, *gitlab.Response, error)
	createDraftNote                    func(pid interface{}, mergeRequestIID int, opt *gitlab.CreateDraftNoteOptions, options ...gitlab.RequestOptionFunc) (*gitlab.DraftNote, *gitlab.Response, error)
	listDraftNotes                     func(pid interface{}, mergeRequest int, opt *gitlab.ListDraftNotesOptions, options ...gitlab.RequestOptionFunc) ([]*gitlab.DraftNote, *gitlab.Response, error)
}

type Author struct {
	ID        int    `json:"id"`
	Username  string `json:"username"`
	Email     string `json:"email"`
	Name      string `json:"name"`
	State     string `json:"state"`
	AvatarURL string `json:"avatar_url"`
	WebURL    string `json:"web_url"`
}

func (f fakeClient) CreateMergeRequest(pid interface{}, opt *gitlab.CreateMergeRequestOptions, options ...gitlab.RequestOptionFunc) (*gitlab.MergeRequest, *gitlab.Response, error) {
	return f.createMrFn(pid, opt, options...)
}

func (f fakeClient) AcceptMergeRequest(pid interface{}, mergeRequestIID int, opt *gitlab.AcceptMergeRequestOptions, options ...gitlab.RequestOptionFunc) (*gitlab.MergeRequest, *gitlab.Response, error) {
	return f.acceptAndMergeFn(pid, mergeRequestIID, opt, options...)
}

func (f fakeClient) GetMergeRequest(pid interface{}, mergeRequestIID int, opt *gitlab.GetMergeRequestsOptions, options ...gitlab.RequestOptionFunc) (*gitlab.MergeRequest, *gitlab.Response, error) {
	return f.getMergeRequestFn(pid, mergeRequestIID, opt, options...)
}

func (f fakeClient) UpdateMergeRequest(pid interface{}, mergeRequestIID int, opt *gitlab.UpdateMergeRequestOptions, options ...gitlab.RequestOptionFunc) (*gitlab.MergeRequest, *gitlab.Response, error) {
	return f.updateMergeRequestFn(pid, mergeRequestIID, opt, options...)
}

func (f fakeClient) UnapproveMergeRequest(pid interface{}, mergeRequestIID int, options ...gitlab.RequestOptionFunc) (*gitlab.Response, error) {
	return f.unapprorveMergeRequestFn(pid, mergeRequestIID, options...)
}

func (f fakeClient) UploadFile(pid interface{}, content io.Reader, filename string, options ...gitlab.RequestOptionFunc) (*gitlab.ProjectFile, *gitlab.Response, error) {
	return f.uploadFile(pid, content, filename, options...)
}

func (f fakeClient) GetMergeRequestDiffVersions(pid interface{}, mergeRequestIID int, opt *gitlab.GetMergeRequestDiffVersionsOptions, options ...gitlab.RequestOptionFunc) ([]*gitlab.MergeRequestDiffVersion, *gitlab.Response, error) {
	return f.getMergeRequestDiffVersions(pid, mergeRequestIID, opt, options...)
}

func (f fakeClient) ApproveMergeRequest(pid interface{}, mergeRequestIID int, opt *gitlab.ApproveMergeRequestOptions, options ...gitlab.RequestOptionFunc) (*gitlab.MergeRequestApprovals, *gitlab.Response, error) {
	return f.approveMergeRequest(pid, mergeRequestIID, opt, options...)
}

func (f fakeClient) ListMergeRequestDiscussions(pid interface{}, mergeRequestIID int, opt *gitlab.ListMergeRequestDiscussionsOptions, options ...gitlab.RequestOptionFunc) ([]*gitlab.Discussion, *gitlab.Response, error) {
	return f.listMergeRequestDiscussions(pid, mergeRequestIID, opt, options...)
}

func (f fakeClient) ResolveMergeRequestDiscussion(pid interface{}, mergeRequestIID int, discussion string, opt *gitlab.ResolveMergeRequestDiscussionOptions, options ...gitlab.RequestOptionFunc) (*gitlab.Discussion, *gitlab.Response, error) {
	return f.resolveMergeRequestDiscussion(pid, mergeRequestIID, discussion, opt, options...)
}

func (f fakeClient) CreateMergeRequestDiscussion(pid interface{}, mergeRequestIID int, opt *gitlab.CreateMergeRequestDiscussionOptions, options ...gitlab.RequestOptionFunc) (*gitlab.Discussion, *gitlab.Response, error) {
	return f.createMergeRequestDiscussion(pid, mergeRequestIID, opt, options...)
}

func (f fakeClient) UpdateMergeRequestDiscussionNote(pid interface{}, mergeRequestIID int, discussion string, note int, opt *gitlab.UpdateMergeRequestDiscussionNoteOptions, options ...gitlab.RequestOptionFunc) (*gitlab.Note, *gitlab.Response, error) {
	return f.updateMergeRequestDiscussionNote(pid, mergeRequestIID, discussion, note, opt, options...)
}

func (f fakeClient) DeleteMergeRequestDiscussionNote(pid interface{}, mergeRequestIID int, discussion string, note int, options ...gitlab.RequestOptionFunc) (*gitlab.Response, error) {
	return f.deleteMergeRequestDiscussionNote(pid, mergeRequestIID, discussion, note, options...)
}

func (f fakeClient) AddMergeRequestDiscussionNote(pid interface{}, mergeRequestIID int, discussion string, opt *gitlab.AddMergeRequestDiscussionNoteOptions, options ...gitlab.RequestOptionFunc) (*gitlab.Note, *gitlab.Response, error) {
	return f.addMergeRequestDiscussionNote(pid, mergeRequestIID, discussion, opt, options...)
}

func (f fakeClient) ListAllProjectMembers(pid interface{}, opt *gitlab.ListProjectMembersOptions, options ...gitlab.RequestOptionFunc) ([]*gitlab.ProjectMember, *gitlab.Response, error) {
	return f.listAllProjectMembers(pid, opt, options...)
}

func (f fakeClient) RetryPipelineBuild(pid interface{}, pipeline int, options ...gitlab.RequestOptionFunc) (*gitlab.Pipeline, *gitlab.Response, error) {
	return f.retryPipelineBuild(pid, pipeline, options...)
}

func (f fakeClient) ListPipelineJobs(pid interface{}, pipelineID int, opts *gitlab.ListJobsOptions, options ...gitlab.RequestOptionFunc) ([]*gitlab.Job, *gitlab.Response, error) {
	return f.listPipelineJobs(pid, pipelineID, opts, options...)
}

func (f fakeClient) GetLatestPipeline(pid interface{}, opts *gitlab.GetLatestPipelineOptions, options ...gitlab.RequestOptionFunc) (*gitlab.Pipeline, *gitlab.Response, error) {
	return f.getLatestPipeline(pid, opts, options...)
}

func (f fakeClient) GetTraceFile(pid interface{}, jobID int, options ...gitlab.RequestOptionFunc) (*bytes.Reader, *gitlab.Response, error) {
	return f.getTraceFile(pid, jobID, options...)
}

func (f fakeClient) ListLabels(pid interface{}, opt *gitlab.ListLabelsOptions, options ...gitlab.RequestOptionFunc) ([]*gitlab.Label, *gitlab.Response, error) {
	return f.listLabels(pid, opt, options...)
}

func (f fakeClient) ListMergeRequestAwardEmojiOnNote(pid interface{}, mergeRequestIID int, noteID int, opt *gitlab.ListAwardEmojiOptions, options ...gitlab.RequestOptionFunc) ([]*gitlab.AwardEmoji, *gitlab.Response, error) {
	return f.listMergeRequestAwardEmojiOnNote(pid, mergeRequestIID, noteID, opt, options...)
}

func (f fakeClient) DeleteMergeRequestAwardEmojiOnNote(pid interface{}, mergeRequestIID, noteID, awardID int, options ...gitlab.RequestOptionFunc) (*gitlab.Response, error) {
	return f.deleteMergeRequestAwardEmojiOnNote(pid, mergeRequestIID, noteID, awardID)
}

func (f fakeClient) CreateDraftNote(pid interface{}, mergeRequestIID int, opt *gitlab.CreateDraftNoteOptions, options ...gitlab.RequestOptionFunc) (*gitlab.DraftNote, *gitlab.Response, error) {
	return f.createDraftNote(pid, mergeRequestIID, opt)
}

func (f fakeClient) ListDraftNotes(pid interface{}, mergeRequestIID int, opt *gitlab.ListDraftNotesOptions, options ...gitlab.RequestOptionFunc) ([]*gitlab.DraftNote, *gitlab.Response, error) {
	return f.listDraftNotes(pid, mergeRequestIID, opt)
}

func (f fakeClient) CurrentUser(options ...gitlab.RequestOptionFunc) (*gitlab.User, *gitlab.Response, error) {
	return f.currentUser()
}

/* This middleware function needs to return an ID for the rest of the handlers */
func (f fakeClient) ListProjectMergeRequests(pid interface{}, opt *gitlab.ListProjectMergeRequestsOptions, options ...gitlab.RequestOptionFunc) ([]*gitlab.MergeRequest, *gitlab.Response, error) {
	return []*gitlab.MergeRequest{{ID: 1}}, &gitlab.Response{}, nil
}

func (f fakeClient) CreateMergeRequestAwardEmojiOnNote(pid interface{}, mergeRequestIID, noteID int, opt *gitlab.CreateAwardEmojiOptions, options ...gitlab.RequestOptionFunc) (*gitlab.AwardEmoji, *gitlab.Response, error) {
	return &gitlab.AwardEmoji{}, &gitlab.Response{}, nil
}

/* The assert function is a helper function used to check two comparables */
func assert[T comparable](t *testing.T, got T, want T) {
	t.Helper()
	if got != want {
		t.Errorf("Got '%v' but wanted '%v'", got, want)
	}
}

/* Will create a new request with the given method, endpoint and body */
func makeRequest(t *testing.T, method string, endpoint string, body any) *http.Request {
	t.Helper()

	var reader io.Reader
	if body != nil {
		j, err := json.Marshal(body)
		if err != nil {
			t.Fatal(err)
		}
		reader = bytes.NewReader(j)
	}

	request, err := http.NewRequest(method, endpoint, reader)
	if err != nil {
		t.Fatal(err)
	}

	return request
}

/* Serves and parses the JSON from an endpoint into the given type */
func serveRequest[T any](t *testing.T, s *http.ServeMux, request *http.Request, i T) *T {
	t.Helper()
	recorder := httptest.NewRecorder()
	s.ServeHTTP(recorder, request)
	result := recorder.Result()
	decoder := json.NewDecoder(result.Body)
	err := decoder.Decode(&i)
	if err != nil {
		t.Fatal(err)
		return nil
	}

	return &i
}

/* Make response makes a simple response value with the right status code */
func makeResponse(status int) *gitlab.Response {
	return &gitlab.Response{
		Response: &http.Response{
			StatusCode: status,
		},
	}
}

func checkErrorFromGitlab(t *testing.T, data ErrorResponse, msg string) {
	t.Helper()
	assert(t, data.Status, http.StatusInternalServerError)
	assert(t, data.Message, msg)
	assert(t, data.Details, "Some error from Gitlab")
}

func checkBadMethod(t *testing.T, data ErrorResponse, methods ...string) {
	t.Helper()
	assert(t, data.Status, http.StatusMethodNotAllowed)
	assert(t, data.Details, "Invalid request type")
	expectedMethods := strings.Join(methods, " or ")
	assert(t, data.Message, fmt.Sprintf("Expected %s", expectedMethods))
}

func checkNon200(t *testing.T, data ErrorResponse, msg, endpoint string) {
	t.Helper()
	assert(t, data.Status, http.StatusSeeOther)
	assert(t, data.Message, msg)
	assert(t, data.Details, fmt.Sprintf("An error occurred on the %s endpoint", endpoint))
}
