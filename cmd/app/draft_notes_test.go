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
}

// var testDraftNotePublishRequest = DraftNotePublishRequest{
// 	Note:       3,
// 	PublishAll: false,
// }

// func TestEditDraftNote(t *testing.T) {
// 	t.Run("Edits draft note", func(t *testing.T) {
// 		client := mock_main.NewMockClient(t)
// 		mock_main.WithMr(t, client)
// 		urlId := 10
// 		client.EXPECT().UpdateDraftNote("", mock_main.MergeId, urlId, gomock.Any()).Return(&gitlab.DraftNote{}, makeResponse(http.StatusOK), nil)
//
// 		request := makeRequest(t, http.MethodPatch, fmt.Sprintf("/mr/draft_notes/%d", urlId), testUpdateDraftNoteRequest)
// 		server := CreateRouter(client)
// 		data := serveRequest(t, server, request, DraftNoteResponse{})
//
// 		assert(t, data.Message, "Draft note updated")
// 		assert(t, data.Status, http.StatusOK)
// 	})
//
// 	t.Run("Handles bad ID", func(t *testing.T) {
// 		client := mock_main.NewMockClient(t)
// 		mock_main.WithMr(t, client)
// 		urlId := "abc"
// 		client.EXPECT().UpdateDraftNote("", mock_main.MergeId, urlId, gomock.Any()).Return(&gitlab.DraftNote{}, makeResponse(http.StatusOK), nil)
//
// 		request := makeRequest(t, http.MethodPatch, fmt.Sprintf("/mr/draft_notes/%s", urlId), testUpdateDraftNoteRequest)
// 		server := CreateRouter(client)
// 		data := serveRequest(t, server, request, ErrorResponse{})
//
// 		assert(t, data.Message, "Could not parse draft note ID")
// 		assert(t, data.Status, http.StatusBadRequest)
// 	})
//
// 	t.Run("Handles empty note", func(t *testing.T) {
// 		client := mock_main.NewMockClient(t)
// 		mock_main.WithMr(t, client)
// 		urlId := 10
//
// 		testEmptyUpdateDraftNoteRequest := testUpdateDraftNoteRequest
// 		testEmptyUpdateDraftNoteRequest.Note = ""
//
// 		client.EXPECT().UpdateDraftNote("", mock_main.MergeId, urlId, gomock.Any()).Return(&gitlab.DraftNote{}, makeResponse(http.StatusOK), nil)
//
// 		request := makeRequest(t, http.MethodPatch, fmt.Sprintf("/mr/draft_notes/%d", urlId), testEmptyUpdateDraftNoteRequest)
// 		server := CreateRouter(client)
// 		data := serveRequest(t, server, request, ErrorResponse{})
//
// 		assert(t, data.Message, "Must provide draft note text")
// 		assert(t, data.Status, http.StatusBadRequest)
// 	})
// }
//
// func TestPublishDraftNote(t *testing.T) {
// 	t.Run("Should publish a draft note", func(t *testing.T) {
// 		client := mock_main.NewMockClient(t)
// 		mock_main.WithMr(t, client)
// 		client.EXPECT().PublishDraftNote("", mock_main.MergeId, testDraftNotePublishRequest.Note).Return(makeResponse(http.StatusOK), nil)
//
// 		request := makeRequest(t, http.MethodPost, "/mr/draft_notes/publish", testDraftNotePublishRequest)
// 		server := CreateRouter(client)
//
// 		data := serveRequest(t, server, request, SuccessResponse{})
// 		assert(t, data.Message, "Draft note(s) published")
// 		assert(t, data.Status, http.StatusOK)
// 	})
//
// 	t.Run("Handles bad/missing ID", func(t *testing.T) {
// 		client := mock_main.NewMockClient(t)
// 		mock_main.WithMr(t, client)
//
// 		// Missing Note ID
// 		testDraftNotePublishRequest := DraftNotePublishRequest{
// 			PublishAll: false,
// 		}
//
// 		request := makeRequest(t, http.MethodPost, "/mr/draft_notes/publish", testDraftNotePublishRequest)
// 		server := CreateRouter(client)
//
// 		data := serveRequest(t, server, request, ErrorResponse{})
// 		assert(t, data.Message, "Must provide Note ID")
// 		assert(t, data.Status, http.StatusBadRequest)
// 	})
//
// 	t.Run("Handles error", func(t *testing.T) {
// 		client := mock_main.NewMockClient(t)
// 		mock_main.WithMr(t, client)
// 		client.EXPECT().PublishDraftNote("", mock_main.MergeId, testDraftNotePublishRequest.Note).Return(nil, errorFromGitlab)
//
// 		request := makeRequest(t, http.MethodPost, "/mr/draft_notes/publish", testDraftNotePublishRequest)
// 		server := CreateRouter(client)
// 		data := serveRequest(t, server, request, ErrorResponse{})
//
// 		assert(t, data.Message, "Could not publish draft note(s)")
// 		assert(t, data.Status, http.StatusInternalServerError)
// 	})
// }
//
// func TestPublishAllDraftNotes(t *testing.T) {
// 	t.Run("Should publish all draft notes", func(t *testing.T) {
// 		client := mock_main.NewMockClient(t)
// 		mock_main.WithMr(t, client)
// 		client.EXPECT().PublishAllDraftNotes("", mock_main.MergeId).Return(makeResponse(http.StatusOK), nil)
//
// 		request := makeRequest(t, http.MethodPost, "/mr/draft_notes/publish", DraftNotePublishRequest{PublishAll: true})
// 		server := CreateRouter(client)
//
// 		data := serveRequest(t, server, request, SuccessResponse{})
// 		assert(t, data.Message, "Draft note(s) published")
// 		assert(t, data.Status, http.StatusOK)
// 	})
//
// 	t.Run("Should handle an error", func(t *testing.T) {
// 		client := mock_main.NewMockClient(t)
// 		mock_main.WithMr(t, client)
// 		client.EXPECT().PublishAllDraftNotes("", mock_main.MergeId).Return(nil, errorFromGitlab)
//
// 		request := makeRequest(t, http.MethodPost, "/mr/draft_notes/publish", DraftNotePublishRequest{PublishAll: true})
// 		server := CreateRouter(client)
//
// 		data := serveRequest(t, server, request, ErrorResponse{})
// 		assert(t, data.Message, "Could not publish draft note(s)")
// 		assert(t, data.Status, http.StatusInternalServerError)
// 	})
// }
