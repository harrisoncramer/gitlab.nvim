package main

import (
	"errors"
	"net/http"
	"testing"

	"github.com/xanzy/go-gitlab"
)

func listDraftNotes(pid interface{}, mergeRequest int, opt *gitlab.ListDraftNotesOptions, options ...gitlab.RequestOptionFunc) ([]*gitlab.DraftNote, *gitlab.Response, error) {
	return []*gitlab.DraftNote{}, makeResponse(http.StatusOK), nil
}

func listDraftNotesErr(pid interface{}, mergeRequest int, opt *gitlab.ListDraftNotesOptions, options ...gitlab.RequestOptionFunc) ([]*gitlab.DraftNote, *gitlab.Response, error) {
	return nil, makeResponse(http.StatusInternalServerError), errors.New("Some error")
}

func TestListDraftNotes(t *testing.T) {
	t.Run("Lists all draft notes", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/mr/draft_notes/", nil)
		server, _ := createRouterAndApi(fakeClient{listDraftNotes: listDraftNotes})
		data := serveRequest(t, server, request, ListDraftNotesResponse{})

		assert(t, data.SuccessResponse.Message, "Draft notes fetched successfully")
		assert(t, data.SuccessResponse.Status, http.StatusOK)
	})

	t.Run("Handles error", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/mr/draft_notes/", nil)
		server, _ := createRouterAndApi(fakeClient{listDraftNotes: listDraftNotesErr})
		data := serveRequest(t, server, request, ErrorResponse{})

		assert(t, data.Message, "Could not get draft notes")
		assert(t, data.Status, http.StatusInternalServerError)
		assert(t, data.Details, "Some error")
	})
}

func createDraftNote(pid interface{}, mergeRequestIID int, opt *gitlab.CreateDraftNoteOptions, options ...gitlab.RequestOptionFunc) (*gitlab.DraftNote, *gitlab.Response, error) {
	return &gitlab.DraftNote{}, makeResponse(http.StatusOK), nil
}

func createDraftNoteErr(pid interface{}, mergeRequestIID int, opt *gitlab.CreateDraftNoteOptions, options ...gitlab.RequestOptionFunc) (*gitlab.DraftNote, *gitlab.Response, error) {
	return nil, makeResponse(http.StatusInternalServerError), errors.New("Some error")
}

func TestPostDraftNote(t *testing.T) {
	t.Run("Posts new draft note", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/mr/draft_notes/", PostDraftNoteRequest{})
		server, _ := createRouterAndApi(fakeClient{createDraftNote: createDraftNote})

		data := serveRequest(t, server, request, DraftNoteResponse{})

		assert(t, data.SuccessResponse.Message, "Draft note created successfully")
		assert(t, data.SuccessResponse.Status, http.StatusOK)
	})

	t.Run("Handles errors on draft note creation", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/mr/draft_notes/", PostDraftNoteRequest{})
		server, _ := createRouterAndApi(fakeClient{createDraftNote: createDraftNoteErr})
		data := serveRequest(t, server, request, ErrorResponse{})
		assert(t, data.Message, "Could not create draft note")
		assert(t, data.Status, http.StatusInternalServerError)
		assert(t, data.Details, "Some error")
	})
}

func deleteDraftNote(pid interface{}, mergeRequest int, note int, options ...gitlab.RequestOptionFunc) (*gitlab.Response, error) {
	return makeResponse(http.StatusOK), nil
}

func deleteDraftNoteErr(pid interface{}, mergeRequest int, note int, options ...gitlab.RequestOptionFunc) (*gitlab.Response, error) {
	return makeResponse(http.StatusInternalServerError), errors.New("Something went wrong")
}

func TestDeleteDraftNote(t *testing.T) {
	t.Run("Deletes draft note", func(t *testing.T) {
		request := makeRequest(t, http.MethodDelete, "/mr/draft_notes/3", nil)
		server, _ := createRouterAndApi(fakeClient{deleteDraftNote: deleteDraftNote})
		data := serveRequest(t, server, request, SuccessResponse{})
		assert(t, data.Message, "Draft note deleted")
		assert(t, data.Status, http.StatusOK)
	})

	t.Run("Handles error", func(t *testing.T) {
		request := makeRequest(t, http.MethodDelete, "/mr/draft_notes/3", nil)
		server, _ := createRouterAndApi(fakeClient{deleteDraftNote: deleteDraftNoteErr})
		data := serveRequest(t, server, request, ErrorResponse{})
		assert(t, data.Message, "Could not delete draft note")
		assert(t, data.Status, http.StatusInternalServerError)
	})

	t.Run("Handles bad ID", func(t *testing.T) {
		request := makeRequest(t, http.MethodDelete, "/mr/draft_notes/abc", nil)
		server, _ := createRouterAndApi(fakeClient{deleteDraftNote: deleteDraftNote})
		data := serveRequest(t, server, request, ErrorResponse{})
		assert(t, data.Message, "Could not parse draft note ID")
		assert(t, data.Status, http.StatusBadRequest)
	})
}

func updateDraftNote(pid interface{}, mergeRequest int, note int, opt *gitlab.UpdateDraftNoteOptions, options ...gitlab.RequestOptionFunc) (*gitlab.DraftNote, *gitlab.Response, error) {
	return &gitlab.DraftNote{}, makeResponse(http.StatusOK), nil
}

func TestEditDraftNote(t *testing.T) {
	t.Run("Edits draft note", func(t *testing.T) {
		request := makeRequest(t, http.MethodPatch, "/mr/draft_notes/3", UpdateDraftNoteRequest{Note: "Some new note"})
		server, _ := createRouterAndApi(fakeClient{updateDraftNote: updateDraftNote})
		data := serveRequest(t, server, request, SuccessResponse{})
		assert(t, data.Message, "Draft note updated")
		assert(t, data.Status, http.StatusOK)
	})

	t.Run("Handles bad ID", func(t *testing.T) {
		request := makeRequest(t, http.MethodPatch, "/mr/draft_notes/abc", nil)
		server, _ := createRouterAndApi(fakeClient{updateDraftNote: updateDraftNote})
		data := serveRequest(t, server, request, ErrorResponse{})
		assert(t, data.Message, "Could not parse draft note ID")
		assert(t, data.Status, http.StatusBadRequest)
	})

	t.Run("Handles empty note", func(t *testing.T) {
		request := makeRequest(t, http.MethodPatch, "/mr/draft_notes/3", UpdateDraftNoteRequest{Note: ""})
		server, _ := createRouterAndApi(fakeClient{updateDraftNote: updateDraftNote})
		data := serveRequest(t, server, request, ErrorResponse{})
		assert(t, data.Message, "Must provide draft note text")
		assert(t, data.Status, http.StatusBadRequest)
	})
}

func publishDraftNote(pid interface{}, mergeRequest int, note int, options ...gitlab.RequestOptionFunc) (*gitlab.Response, error) {
	return makeResponse(http.StatusOK), nil
}

func TestPublishDraftNote(t *testing.T) {
	t.Run("Should publish a draft note", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/mr/draft_notes/publish", DraftNotePublishRequest{Note: 3, PublishAll: false})
		server, _ := createRouterAndApi(fakeClient{
			publishDraftNote: publishDraftNote,
		})
		data := serveRequest(t, server, request, SuccessResponse{})
		assert(t, data.Message, "Draft note(s) published")
		assert(t, data.Status, http.StatusOK)
	})
	t.Run("Handles bad ID", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/mr/draft_notes/publish", DraftNotePublishRequest{PublishAll: false})
		server, _ := createRouterAndApi(fakeClient{updateDraftNote: updateDraftNote})
		data := serveRequest(t, server, request, ErrorResponse{})
		assert(t, data.Message, "Must provide Note ID")
		assert(t, data.Status, http.StatusBadRequest)
	})
}
