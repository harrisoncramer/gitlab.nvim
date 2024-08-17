package main

import (
	"errors"
	"fmt"
	"net/http"
	"testing"

	"github.com/xanzy/go-gitlab"
	mock_main "gitlab.com/harrisoncramer/gitlab.nvim/cmd/mocks"
)

var listDraftNoteOpts = gitlab.ListDraftNotesOptions{}

var testPostDraftNoteRequestData = PostDraftNoteRequest{
	Comment: "Some comment",
}

var testPostDraftNoteOpts = gitlab.CreateDraftNoteOptions{
	Note: &testPostDraftNoteRequestData.Comment,
}

var testUpdateDraftNoteRequest = UpdateDraftNoteRequest{
	Note: "Some new note",
}

var testUpdateDraftNoteOpts = gitlab.UpdateDraftNoteOptions{
	Note:     &testUpdateDraftNoteRequest.Note,
	Position: &gitlab.PositionOptions{},
}

func TestListDraftNotes(t *testing.T) {
	t.Run("Lists all draft notes", func(t *testing.T) {
		client := mock_main.NewMockClient(t)
		mock_main.WithMr(t, client)
		client.EXPECT().ListDraftNotes("", mock_main.MergeId, &listDraftNoteOpts).Return([]*gitlab.DraftNote{}, makeResponse(http.StatusOK), nil)

		request := makeRequest(t, http.MethodGet, "/mr/draft_notes/", nil)
		server, _ := CreateRouterAndApi(client)
		data := serveRequest(t, server, request, ListDraftNotesResponse{})

		assert(t, data.SuccessResponse.Message, "Draft notes fetched successfully")
		assert(t, data.SuccessResponse.Status, http.StatusOK)
	})

	t.Run("Handles error", func(t *testing.T) {
		client := mock_main.NewMockClient(t)
		mock_main.WithMr(t, client)
		client.EXPECT().ListDraftNotes("", mock_main.MergeId, &listDraftNoteOpts).Return(nil, nil, errorFromGitlab)

		request := makeRequest(t, http.MethodGet, "/mr/draft_notes/", nil)
		server, _ := CreateRouterAndApi(client)
		data := serveRequest(t, server, request, ErrorResponse{})

		assert(t, data.Message, "Could not get draft notes")
		assert(t, data.Status, http.StatusInternalServerError)
		assert(t, data.Details, errorFromGitlab.Error())
	})
}

func TestPostDraftNote(t *testing.T) {
	t.Run("Posts new draft note", func(t *testing.T) {
		client := mock_main.NewMockClient(t)
		mock_main.WithMr(t, client)
		client.EXPECT().CreateDraftNote("", mock_main.MergeId, &testPostDraftNoteOpts).Return(&gitlab.DraftNote{}, makeResponse(http.StatusOK), nil)

		request := makeRequest(t, http.MethodPost, "/mr/draft_notes/", testPostDraftNoteRequestData)
		server, _ := CreateRouterAndApi(client)
		data := serveRequest(t, server, request, DraftNoteResponse{})

		assert(t, data.SuccessResponse.Message, "Draft note created successfully")
		assert(t, data.SuccessResponse.Status, http.StatusOK)
	})

	t.Run("Handles errors on draft note creation", func(t *testing.T) {
		client := mock_main.NewMockClient(t)
		mock_main.WithMr(t, client)
		client.EXPECT().CreateDraftNote("", mock_main.MergeId, &testPostDraftNoteOpts).Return(nil, nil, errorFromGitlab)

		request := makeRequest(t, http.MethodPost, "/mr/draft_notes/", testPostDraftNoteRequestData)
		server, _ := CreateRouterAndApi(client)
		data := serveRequest(t, server, request, ErrorResponse{})

		assert(t, data.Message, "Could not create draft note")
		assert(t, data.Status, http.StatusInternalServerError)
		assert(t, data.Details, errorFromGitlab.Error())
	})
}

func TestDeleteDraftNote(t *testing.T) {
	t.Run("Deletes draft note", func(t *testing.T) {
		client := mock_main.NewMockClient(t)
		mock_main.WithMr(t, client)
		urlId := 10
		client.EXPECT().DeleteDraftNote("", mock_main.MergeId, urlId).Return(makeResponse(http.StatusOK), nil)

		request := makeRequest(t, http.MethodDelete, fmt.Sprintf("/mr/draft_notes/%d", urlId), nil)
		server, _ := CreateRouterAndApi(client)
		data := serveRequest(t, server, request, DraftNoteResponse{})

		assert(t, data.SuccessResponse.Message, "Draft note deleted")
		assert(t, data.SuccessResponse.Status, http.StatusOK)
	})

	t.Run("Handles error", func(t *testing.T) {
		client := mock_main.NewMockClient(t)
		mock_main.WithMr(t, client)
		urlId := 10
		client.EXPECT().DeleteDraftNote("", mock_main.MergeId, urlId).Return(nil, errorFromGitlab)

		request := makeRequest(t, http.MethodDelete, fmt.Sprintf("/mr/draft_notes/%d", urlId), nil)
		server, _ := CreateRouterAndApi(client)
		data := serveRequest(t, server, request, ErrorResponse{})

		assert(t, data.Message, "Could not delete draft note")
		assert(t, data.Status, http.StatusInternalServerError)
		assert(t, data.Details, errorFromGitlab.Error())
	})

	t.Run("Handles bad ID", func(t *testing.T) {
		client := mock_main.NewMockClient(t)
		mock_main.WithMr(t, client)
		urlId := "abc"

		request := makeRequest(t, http.MethodDelete, fmt.Sprintf("/mr/draft_notes/%s", urlId), nil)
		server, _ := CreateRouterAndApi(client)
		data := serveRequest(t, server, request, ErrorResponse{})

		assert(t, data.Message, "Could not parse draft note ID")
		assert(t, data.Status, http.StatusBadRequest)
	})
}

func TestEditDraftNote(t *testing.T) {
	t.Run("Edits draft note", func(t *testing.T) {
		client := mock_main.NewMockClient(t)
		mock_main.WithMr(t, client)
		urlId := 10
		client.EXPECT().UpdateDraftNote("", mock_main.MergeId, urlId, &testUpdateDraftNoteOpts).Return(&gitlab.DraftNote{}, makeResponse(http.StatusOK), nil)

		request := makeRequest(t, http.MethodPatch, fmt.Sprintf("/mr/draft_notes/%d", urlId), testUpdateDraftNoteRequest)
		server, _ := CreateRouterAndApi(client)
		data := serveRequest(t, server, request, DraftNoteResponse{})

		assert(t, data.Message, "Draft note updated")
		assert(t, data.Status, http.StatusOK)
	})

	t.Run("Handles bad ID", func(t *testing.T) {
		client := mock_main.NewMockClient(t)
		mock_main.WithMr(t, client)
		urlId := "abc"
		client.EXPECT().UpdateDraftNote("", mock_main.MergeId, urlId, &testUpdateDraftNoteOpts).Return(&gitlab.DraftNote{}, makeResponse(http.StatusOK), nil)

		request := makeRequest(t, http.MethodPatch, fmt.Sprintf("/mr/draft_notes/%s", urlId), testUpdateDraftNoteRequest)
		server, _ := CreateRouterAndApi(client)
		data := serveRequest(t, server, request, ErrorResponse{})

		assert(t, data.Message, "Could not parse draft note ID")
		assert(t, data.Status, http.StatusBadRequest)
	})

	t.Run("Handles empty note", func(t *testing.T) {
		client := mock_main.NewMockClient(t)
		mock_main.WithMr(t, client)
		urlId := 10

		testEmptyUpdateDraftNoteRequest := testUpdateDraftNoteRequest
		testEmptyUpdateDraftNoteRequest.Note = ""

		testEmptyUpdateDraftNoteOpts := testUpdateDraftNoteOpts
		testEmptyUpdateDraftNoteOpts.Note = &testEmptyUpdateDraftNoteRequest.Note

		client.EXPECT().UpdateDraftNote("", mock_main.MergeId, urlId, &testEmptyUpdateDraftNoteOpts).Return(&gitlab.DraftNote{}, makeResponse(http.StatusOK), nil)

		request := makeRequest(t, http.MethodPatch, fmt.Sprintf("/mr/draft_notes/%d", urlId), testEmptyUpdateDraftNoteRequest)
		server, _ := CreateRouterAndApi(client)
		data := serveRequest(t, server, request, ErrorResponse{})

		assert(t, data.Message, "Must provide draft note text")
		assert(t, data.Status, http.StatusBadRequest)
	})
}

func publishDraftNote(pid interface{}, mergeRequest int, note int, options ...gitlab.RequestOptionFunc) (*gitlab.Response, error) {
	return makeResponse(http.StatusOK), nil
}

func publishDraftNoteErr(pid interface{}, mergeRequest int, note int, options ...gitlab.RequestOptionFunc) (*gitlab.Response, error) {
	return nil, errors.New("Some error")
}

func TestPublishDraftNote(t *testing.T) {
	t.Run("Should publish a draft note", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/mr/draft_notes/publish", DraftNotePublishRequest{Note: 3, PublishAll: false})
		server, _ := CreateRouterAndApi(fakeClient{
			publishDraftNote: publishDraftNote,
		})
		data := serveRequest(t, server, request, SuccessResponse{})
		assert(t, data.Message, "Draft note(s) published")
		assert(t, data.Status, http.StatusOK)
	})

	t.Run("Handles bad/missing ID", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/mr/draft_notes/publish", DraftNotePublishRequest{PublishAll: false})
		server, _ := CreateRouterAndApi(fakeClient{publishDraftNote: publishDraftNote})
		data := serveRequest(t, server, request, ErrorResponse{})
		assert(t, data.Message, "Must provide Note ID")
		assert(t, data.Status, http.StatusBadRequest)
	})

	t.Run("Handles error", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/mr/draft_notes/publish", DraftNotePublishRequest{PublishAll: false, Note: 3})
		server, _ := CreateRouterAndApi(fakeClient{publishDraftNote: publishDraftNoteErr})
		data := serveRequest(t, server, request, ErrorResponse{})
		assert(t, data.Message, "Could not publish draft note(s)")
		assert(t, data.Status, http.StatusInternalServerError)
	})
}

func publishAllDraftNotes(pid interface{}, mergeRequest int, options ...gitlab.RequestOptionFunc) (*gitlab.Response, error) {
	return makeResponse(http.StatusOK), nil
}

func publishAllDraftNotesErr(pid interface{}, mergeRequest int, options ...gitlab.RequestOptionFunc) (*gitlab.Response, error) {
	return nil, errors.New("Some error")
}

func TestPublishAllDraftNotes(t *testing.T) {
	t.Run("Should publish all draft notes", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/mr/draft_notes/publish", DraftNotePublishRequest{PublishAll: true})
		server, _ := CreateRouterAndApi(fakeClient{
			publishAllDraftNotes: publishAllDraftNotes,
		})
		data := serveRequest(t, server, request, SuccessResponse{})
		assert(t, data.Message, "Draft note(s) published")
		assert(t, data.Status, http.StatusOK)
	})

	t.Run("Should handle an error", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/mr/draft_notes/publish", DraftNotePublishRequest{PublishAll: true})
		server, _ := CreateRouterAndApi(fakeClient{
			publishAllDraftNotes: publishAllDraftNotesErr,
		})
		data := serveRequest(t, server, request, ErrorResponse{})
		assert(t, data.Message, "Could not publish draft note(s)")
		assert(t, data.Status, http.StatusInternalServerError)
	})
}
