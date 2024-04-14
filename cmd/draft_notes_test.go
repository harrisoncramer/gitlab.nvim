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

func TestPostDraftNote(t *testing.T) {
	t.Run("Posts new draft note", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/mr/draft_notes/", PostDraftNoteRequest{})
		server, _ := createRouterAndApi(fakeClient{createDraftNote: createDraftNote})

		data := serveRequest(t, server, request, DraftNoteResponse{})

		assert(t, data.SuccessResponse.Message, "Draft note created successfully")
		assert(t, data.SuccessResponse.Status, http.StatusOK)

	})
}
