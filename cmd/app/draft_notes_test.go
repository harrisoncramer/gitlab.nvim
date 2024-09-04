package app

import (
	"net/http"
	"testing"

	"github.com/xanzy/go-gitlab"
)

type fakeDraftNoteManager struct {
	testBase
}

func (f fakeDraftNoteManager) ListDraftNotes(pid interface{}, mergeRequest int, opt *gitlab.ListDraftNotesOptions, options ...gitlab.RequestOptionFunc) ([]*gitlab.DraftNote, *gitlab.Response, error) {
	resp, err := f.handleGitlabError()
	if err != nil {
		return nil, nil, err
	}
	return []*gitlab.DraftNote{}, resp, err
}

func (f fakeDraftNoteManager) CreateDraftNote(pid interface{}, mergeRequest int, opt *gitlab.CreateDraftNoteOptions, options ...gitlab.RequestOptionFunc) (*gitlab.DraftNote, *gitlab.Response, error) {
	resp, err := f.handleGitlabError()
	if err != nil {
		return nil, nil, err
	}
	return &gitlab.DraftNote{}, resp, err
}

func (f fakeDraftNoteManager) DeleteDraftNote(pid interface{}, mergeRequest int, note int, options ...gitlab.RequestOptionFunc) (*gitlab.Response, error) {
	return f.handleGitlabError()
}

func (f fakeDraftNoteManager) UpdateDraftNote(pid interface{}, mergeRequest int, note int, opt *gitlab.UpdateDraftNoteOptions, options ...gitlab.RequestOptionFunc) (*gitlab.DraftNote, *gitlab.Response, error) {
	resp, err := f.handleGitlabError()
	if err != nil {
		return nil, nil, err
	}
	return &gitlab.DraftNote{}, resp, err
}

func TestListDraftNotes(t *testing.T) {
	t.Run("Lists all draft notes", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/mr/draft_notes/", nil)
		svc := draftNoteService{emptyProjectData, fakeDraftNoteManager{}}
		data := getSuccessData(t, svc, request)
		assert(t, data.Status, http.StatusOK)
		assert(t, data.Message, "Draft notes fetched successfully")
	})
	t.Run("Handles error from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/mr/draft_notes/", nil)
		svc := draftNoteService{emptyProjectData, fakeDraftNoteManager{testBase{errFromGitlab: true}}}
		data := getFailData(t, svc, request)
		checkErrorFromGitlab(t, data, "Could not get draft notes")
	})
	t.Run("Handles non-200s from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/mr/draft_notes/", nil)
		svc := draftNoteService{emptyProjectData, fakeDraftNoteManager{testBase{status: http.StatusSeeOther}}}
		data := getFailData(t, svc, request)
		checkNon200(t, data, "Could not get draft notes", "/mr/draft_notes/")
	})
}

func TestPostDraftNote(t *testing.T) {
	var testPostDraftNoteRequestData = PostDraftNoteRequest{Comment: "Some comment"}
	t.Run("Posts new draft note", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/mr/draft_notes/", testPostDraftNoteRequestData)
		svc := draftNoteService{emptyProjectData, fakeDraftNoteManager{}}
		data := getSuccessData(t, svc, request)
		assert(t, data.Status, http.StatusOK)
		assert(t, data.Message, "Draft note created successfully")
	})
	t.Run("Handles error from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/mr/draft_notes/", testPostDraftNoteRequestData)
		svc := draftNoteService{emptyProjectData, fakeDraftNoteManager{testBase{errFromGitlab: true}}}
		data := getFailData(t, svc, request)
		checkErrorFromGitlab(t, data, "Could not create draft note")
	})
	t.Run("Handles non-200s from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/mr/draft_notes/", testPostDraftNoteRequestData)
		svc := draftNoteService{emptyProjectData, fakeDraftNoteManager{testBase{status: http.StatusSeeOther}}}
		data := getFailData(t, svc, request)
		checkNon200(t, data, "Could not create draft note", "/mr/draft_notes/")
	})
}

func TestDeleteDraftNote(t *testing.T) {
	t.Run("Deletes new draft note", func(t *testing.T) {
		request := makeRequest(t, http.MethodDelete, "/mr/draft_notes/3", nil)
		svc := draftNoteService{emptyProjectData, fakeDraftNoteManager{}}
		data := getSuccessData(t, svc, request)
		assert(t, data.Status, http.StatusOK)
		assert(t, data.Message, "Draft note deleted")
	})
	t.Run("Handles error from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodDelete, "/mr/draft_notes/3", nil)
		svc := draftNoteService{emptyProjectData, fakeDraftNoteManager{testBase{errFromGitlab: true}}}
		data := getFailData(t, svc, request)
		checkErrorFromGitlab(t, data, "Could not delete draft note")
	})
	t.Run("Handles non-200s from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodDelete, "/mr/draft_notes/3", nil)
		svc := draftNoteService{emptyProjectData, fakeDraftNoteManager{testBase{status: http.StatusSeeOther}}}
		data := getFailData(t, svc, request)
		checkNon200(t, data, "Could not delete draft note", "/mr/draft_notes/3")
	})
	t.Run("Handles bad ID", func(t *testing.T) {
		request := makeRequest(t, http.MethodDelete, "/mr/draft_notes/blah", nil)
		svc := draftNoteService{emptyProjectData, fakeDraftNoteManager{testBase{status: http.StatusSeeOther}}}
		data := getFailData(t, svc, request)
		assert(t, data.Message, "Could not parse draft note ID")
		assert(t, data.Status, http.StatusBadRequest)
	})
}

func TestEditDraftNote(t *testing.T) {
	var testUpdateDraftNoteRequest = UpdateDraftNoteRequest{Note: "Some new note"}
	t.Run("Edits new draft note", func(t *testing.T) {
		request := makeRequest(t, http.MethodPatch, "/mr/draft_notes/3", testUpdateDraftNoteRequest)
		svc := draftNoteService{emptyProjectData, fakeDraftNoteManager{}}
		data := getSuccessData(t, svc, request)
		assert(t, data.Status, http.StatusOK)
		assert(t, data.Message, "Draft note updated")
	})
	t.Run("Handles error from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodPatch, "/mr/draft_notes/3", testUpdateDraftNoteRequest)
		svc := draftNoteService{emptyProjectData, fakeDraftNoteManager{testBase{errFromGitlab: true}}}
		data := getFailData(t, svc, request)
		checkErrorFromGitlab(t, data, "Could not update draft note")
	})
	t.Run("Handles non-200s from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodPatch, "/mr/draft_notes/3", testUpdateDraftNoteRequest)
		svc := draftNoteService{emptyProjectData, fakeDraftNoteManager{testBase{status: http.StatusSeeOther}}}
		data := getFailData(t, svc, request)
		checkNon200(t, data, "Could not update draft note", "/mr/draft_notes/3")
	})
	t.Run("Handles bad ID", func(t *testing.T) {
		request := makeRequest(t, http.MethodPatch, "/mr/draft_notes/blah", testUpdateDraftNoteRequest)
		svc := draftNoteService{emptyProjectData, fakeDraftNoteManager{testBase{status: http.StatusSeeOther}}}
		data := getFailData(t, svc, request)
		assert(t, data.Message, "Could not parse draft note ID")
		assert(t, data.Status, http.StatusBadRequest)
	})
	t.Run("Handles empty note", func(t *testing.T) {
		requestData := testUpdateDraftNoteRequest
		requestData.Note = ""
		request := makeRequest(t, http.MethodPatch, "/mr/draft_notes/3", requestData)
		svc := draftNoteService{emptyProjectData, fakeDraftNoteManager{testBase{status: http.StatusSeeOther}}}
		data := getFailData(t, svc, request)
		assert(t, data.Message, "Must provide draft note text")
		assert(t, data.Status, http.StatusBadRequest)
	})
}
