package app

import (
	"net/http"
	"testing"

	"github.com/xanzy/go-gitlab"
)

type fakeDraftNotePublisher struct {
	testBase
}

func (f fakeDraftNotePublisher) PublishAllDraftNotes(pid interface{}, mergeRequest int, options ...gitlab.RequestOptionFunc) (*gitlab.Response, error) {
	return f.handleGitlabError()
}
func (f fakeDraftNotePublisher) PublishDraftNote(pid interface{}, mergeRequest int, note int, options ...gitlab.RequestOptionFunc) (*gitlab.Response, error) {
	return f.handleGitlabError()
}

func TestPublishDraftNote(t *testing.T) {
	var testDraftNotePublishRequest = DraftNotePublishRequest{Note: 3, PublishAll: false}
	t.Run("Publishes draft note", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/mr/draft_notes/publish", testDraftNotePublishRequest)
		svc := draftNotePublisherService{testProjectData, fakeDraftNotePublisher{}}
		data := getSuccessData(t, svc, request)
		assert(t, data.Status, http.StatusOK)
		assert(t, data.Message, "Draft note(s) published")
	})
	t.Run("Disallows non-POST method", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/mr/draft_notes/publish", testDraftNotePublishRequest)
		svc := draftNotePublisherService{testProjectData, fakeDraftNotePublisher{}}
		data := getFailData(t, svc, request)
		checkBadMethod(t, data, http.MethodPost)
	})
	t.Run("Handles bad ID", func(t *testing.T) {
		badData := testDraftNotePublishRequest
		badData.Note = 0
		request := makeRequest(t, http.MethodPost, "/mr/draft_notes/publish", badData)
		svc := draftNotePublisherService{testProjectData, fakeDraftNotePublisher{}}
		data := getFailData(t, svc, request)
		assert(t, data.Status, http.StatusBadRequest)
		assert(t, data.Message, "Must provide Note ID")
	})
	t.Run("Handles error from Gitlab", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/mr/draft_notes/publish", testDraftNotePublishRequest)
		svc := draftNotePublisherService{testProjectData, fakeDraftNotePublisher{testBase{errFromGitlab: true}}}
		data := getFailData(t, svc, request)
		checkErrorFromGitlab(t, data, "Could not publish draft note(s)")
	})
}

func TestPublishAllDraftNotes(t *testing.T) {
	var testDraftNotePublishRequest = DraftNotePublishRequest{PublishAll: true}
	t.Run("Should publish all draft notes", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/mr/draft_notes/publish", testDraftNotePublishRequest)
		svc := draftNotePublisherService{testProjectData, fakeDraftNotePublisher{}}
		data := getSuccessData(t, svc, request)
		assert(t, data.Status, http.StatusOK)
		assert(t, data.Message, "Draft note(s) published")
	})
	t.Run("Disallows non-POST method", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/mr/draft_notes/publish", testDraftNotePublishRequest)
		svc := draftNotePublisherService{testProjectData, fakeDraftNotePublisher{}}
		data := getFailData(t, svc, request)
		checkBadMethod(t, data, http.MethodPost)
	})
	t.Run("Handles error from Gitlab", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/mr/draft_notes/publish", testDraftNotePublishRequest)
		svc := draftNotePublisherService{testProjectData, fakeDraftNotePublisher{testBase{errFromGitlab: true}}}
		data := getFailData(t, svc, request)
		checkErrorFromGitlab(t, data, "Could not publish draft note(s)")
	})
}
