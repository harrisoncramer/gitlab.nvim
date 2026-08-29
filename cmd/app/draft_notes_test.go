package app

import (
	"net/http"
	"testing"

	gitlab "gitlab.com/gitlab-org/api/client-go"
)

type fakeDraftNoteManager struct {
	testBase
	capturedOpt **gitlab.CreateDraftNoteOptions
}

func (f fakeDraftNoteManager) ListDraftNotes(pid interface{}, mergeRequest int64, opt *gitlab.ListDraftNotesOptions, options ...gitlab.RequestOptionFunc) ([]*gitlab.DraftNote, *gitlab.Response, error) {
	resp, err := f.handleGitlabError()
	if err != nil {
		return nil, nil, err
	}
	return []*gitlab.DraftNote{}, resp, err
}

func (f fakeDraftNoteManager) CreateDraftNote(pid interface{}, mergeRequest int64, opt *gitlab.CreateDraftNoteOptions, options ...gitlab.RequestOptionFunc) (*gitlab.DraftNote, *gitlab.Response, error) {
	resp, err := f.handleGitlabError()
	if err != nil {
		return nil, nil, err
	}
	if f.capturedOpt != nil {
		*f.capturedOpt = opt
	}
	return &gitlab.DraftNote{}, resp, err
}

func (f fakeDraftNoteManager) DeleteDraftNote(pid interface{}, mergeRequest int64, note int64, options ...gitlab.RequestOptionFunc) (*gitlab.Response, error) {
	return f.handleGitlabError()
}

func (f fakeDraftNoteManager) UpdateDraftNote(pid interface{}, mergeRequest int64, note int64, opt *gitlab.UpdateDraftNoteOptions, options ...gitlab.RequestOptionFunc) (*gitlab.DraftNote, *gitlab.Response, error) {
	resp, err := f.handleGitlabError()
	if err != nil {
		return nil, nil, err
	}
	return &gitlab.DraftNote{}, resp, err
}

func TestListDraftNotes(t *testing.T) {
	t.Run("Lists all draft notes", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/mr/draft_notes/", nil)
		svc := middleware(
			draftNoteService{testProjectData, fakeDraftNoteManager{}},
			withMr(testProjectData, fakeMergeRequestLister{}),
			withPayloadValidation(methodToPayload{
				http.MethodPost:  newPayload[PostDraftNoteRequest],
				http.MethodPatch: newPayload[UpdateDraftNoteRequest],
			}),
			withMethodCheck(http.MethodGet, http.MethodPost, http.MethodPatch, http.MethodDelete),
		)

		data := getSuccessData(t, svc, request)
		assert(t, data.Message, "Draft notes fetched successfully")
	})
	t.Run("Handles error from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/mr/draft_notes/", nil)
		svc := middleware(
			draftNoteService{testProjectData, fakeDraftNoteManager{testBase: testBase{errFromGitlab: true}}},
			withMr(testProjectData, fakeMergeRequestLister{}),
			withPayloadValidation(methodToPayload{
				http.MethodPost:  newPayload[PostDraftNoteRequest],
				http.MethodPatch: newPayload[UpdateDraftNoteRequest],
			}),
			withMethodCheck(http.MethodGet, http.MethodPost, http.MethodPatch, http.MethodDelete),
		)
		data, _ := getFailData(t, svc, request)
		checkErrorFromGitlab(t, data, "Could not get draft notes")
	})
	t.Run("Handles non-200s from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/mr/draft_notes/", nil)
		svc := middleware(
			draftNoteService{testProjectData, fakeDraftNoteManager{testBase: testBase{status: http.StatusSeeOther}}},
			withMr(testProjectData, fakeMergeRequestLister{}),
			withPayloadValidation(methodToPayload{
				http.MethodPost:  newPayload[PostDraftNoteRequest],
				http.MethodPatch: newPayload[UpdateDraftNoteRequest],
			}),
			withMethodCheck(http.MethodGet, http.MethodPost, http.MethodPatch, http.MethodDelete),
		)
		data, _ := getFailData(t, svc, request)
		checkNon200(t, data, "Could not get draft notes", "/mr/draft_notes/")
	})
}

func TestPostDraftNote(t *testing.T) {
	var testPostDraftNoteRequestData = PostDraftNoteRequest{
		Comment:      "Some comment",
		DiscussionId: "abc123",
	}
	t.Run("Posts new draft note", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/mr/draft_notes/", testPostDraftNoteRequestData)
		svc := middleware(
			draftNoteService{testProjectData, fakeDraftNoteManager{}},
			withMr(testProjectData, fakeMergeRequestLister{}),
			withPayloadValidation(methodToPayload{
				http.MethodPost:  newPayload[PostDraftNoteRequest],
				http.MethodPatch: newPayload[UpdateDraftNoteRequest],
			}),
			withMethodCheck(http.MethodGet, http.MethodPost, http.MethodPatch, http.MethodDelete),
		)
		data := getSuccessData(t, svc, request)
		assert(t, data.Message, "Draft note created successfully")
	})

	t.Run("Passes commit_id through to the Gitlab client when provided", func(t *testing.T) {
		testData := PostDraftNoteRequest{
			Comment: "Some comment",
			PositionData: PositionData{
				FileName: "file.txt",
				CommitID: "abc123",
				LineRange: &LineRange{
					Start: &PositionInfo{Type: "", OldLine: 4, NewLine: 4},
					End:   &PositionInfo{Type: "", OldLine: 4, NewLine: 4},
				},
			},
		}
		request := makeRequest(t, http.MethodPost, "/mr/draft_notes/", testData)
		var capturedOpt *gitlab.CreateDraftNoteOptions
		svc := middleware(
			draftNoteService{testProjectData, fakeDraftNoteManager{capturedOpt: &capturedOpt}},
			withMr(testProjectData, fakeMergeRequestLister{}),
			withPayloadValidation(methodToPayload{
				http.MethodPost:  newPayload[PostDraftNoteRequest],
				http.MethodPatch: newPayload[UpdateDraftNoteRequest],
			}),
			withMethodCheck(http.MethodGet, http.MethodPost, http.MethodPatch, http.MethodDelete),
		)
		getSuccessData(t, svc, request)
		if capturedOpt.CommitID == nil {
			t.Fatal("expected CommitID to be set")
		}
		assert(t, *capturedOpt.CommitID, "abc123")
	})

	t.Run("Leaves commit_id unset when not provided", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/mr/draft_notes/", testPostDraftNoteRequestData)
		var capturedOpt *gitlab.CreateDraftNoteOptions
		svc := middleware(
			draftNoteService{testProjectData, fakeDraftNoteManager{capturedOpt: &capturedOpt}},
			withMr(testProjectData, fakeMergeRequestLister{}),
			withPayloadValidation(methodToPayload{
				http.MethodPost:  newPayload[PostDraftNoteRequest],
				http.MethodPatch: newPayload[UpdateDraftNoteRequest],
			}),
			withMethodCheck(http.MethodGet, http.MethodPost, http.MethodPatch, http.MethodDelete),
		)
		getSuccessData(t, svc, request)
		if capturedOpt.CommitID != nil {
			t.Fatalf("expected CommitID to be nil, got %q", *capturedOpt.CommitID)
		}
	})
}

func TestDeleteDraftNote(t *testing.T) {
	t.Run("Deletes new draft note", func(t *testing.T) {
		request := makeRequest(t, http.MethodDelete, "/mr/draft_notes/3", nil)
		svc := middleware(
			draftNoteService{testProjectData, fakeDraftNoteManager{}},
			withMr(testProjectData, fakeMergeRequestLister{}),
			withPayloadValidation(methodToPayload{
				http.MethodPost:  newPayload[PostDraftNoteRequest],
				http.MethodPatch: newPayload[UpdateDraftNoteRequest],
			}),
			withMethodCheck(http.MethodGet, http.MethodPost, http.MethodPatch, http.MethodDelete),
		)
		data := getSuccessData(t, svc, request)
		assert(t, data.Message, "Draft note deleted")
	})
	t.Run("Handles bad ID", func(t *testing.T) {
		request := makeRequest(t, http.MethodDelete, "/mr/draft_notes/blah", nil)
		svc := middleware(
			draftNoteService{testProjectData, fakeDraftNoteManager{}},
			withMr(testProjectData, fakeMergeRequestLister{}),
			withPayloadValidation(methodToPayload{
				http.MethodPost:  newPayload[PostDraftNoteRequest],
				http.MethodPatch: newPayload[UpdateDraftNoteRequest],
			}),
			withMethodCheck(http.MethodGet, http.MethodPost, http.MethodPatch, http.MethodDelete),
		)
		data, status := getFailData(t, svc, request)
		assert(t, data.Message, "Could not parse draft note ID")
		assert(t, status, http.StatusBadRequest)
	})
}

func TestEditDraftNote(t *testing.T) {
	var testUpdateDraftNoteRequest = UpdateDraftNoteRequest{Note: "Some new note"}
	t.Run("Edits new draft note", func(t *testing.T) {
		request := makeRequest(t, http.MethodPatch, "/mr/draft_notes/3", testUpdateDraftNoteRequest)
		svc := middleware(
			draftNoteService{testProjectData, fakeDraftNoteManager{}},
			withMr(testProjectData, fakeMergeRequestLister{}),
			withPayloadValidation(methodToPayload{
				http.MethodPost:  newPayload[PostDraftNoteRequest],
				http.MethodPatch: newPayload[UpdateDraftNoteRequest],
			}),
			withMethodCheck(http.MethodGet, http.MethodPost, http.MethodPatch, http.MethodDelete),
		)
		data := getSuccessData(t, svc, request)
		assert(t, data.Message, "Draft note updated")
	})
	t.Run("Handles bad ID", func(t *testing.T) {
		request := makeRequest(t, http.MethodPatch, "/mr/draft_notes/blah", testUpdateDraftNoteRequest)
		svc := middleware(
			draftNoteService{testProjectData, fakeDraftNoteManager{}},
			withMr(testProjectData, fakeMergeRequestLister{}),
			withPayloadValidation(methodToPayload{
				http.MethodPost:  newPayload[PostDraftNoteRequest],
				http.MethodPatch: newPayload[UpdateDraftNoteRequest],
			}),
			withMethodCheck(http.MethodGet, http.MethodPost, http.MethodPatch, http.MethodDelete),
		)
		data, status := getFailData(t, svc, request)
		assert(t, data.Message, "Could not parse draft note ID")
		assert(t, status, http.StatusBadRequest)
	})
	t.Run("Handles empty note", func(t *testing.T) {
		requestData := testUpdateDraftNoteRequest
		requestData.Note = ""
		request := makeRequest(t, http.MethodPatch, "/mr/draft_notes/3", requestData)
		svc := middleware(
			draftNoteService{testProjectData, fakeDraftNoteManager{}},
			withMr(testProjectData, fakeMergeRequestLister{}),
			withPayloadValidation(methodToPayload{
				http.MethodPost:  newPayload[PostDraftNoteRequest],
				http.MethodPatch: newPayload[UpdateDraftNoteRequest],
			}),
			withMethodCheck(http.MethodGet, http.MethodPost, http.MethodPatch, http.MethodDelete),
		)
		data, status := getFailData(t, svc, request)
		assert(t, data.Message, "Invalid payload")
		assert(t, data.Details, "Note is required")
		assert(t, status, http.StatusBadRequest)
	})
}
