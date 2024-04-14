package main

import (
	"net/http"
	"testing"

	"github.com/xanzy/go-gitlab"
)

func listDraftNotes(pid interface{}, mergeRequest int, opt *gitlab.ListDraftNotesOptions, options ...gitlab.RequestOptionFunc) ([]*gitlab.DraftNote, *gitlab.Response, error) {
	return []*gitlab.DraftNote{}, makeResponse(http.StatusOK), nil
}

func TestListDraftNotes(t *testing.T) {
	t.Run("Lists all draft notes", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/mr/draft_notes/", nil)
		server, _ := createRouterAndApi(fakeClient{listDraftNotes: listDraftNotes})
		data := serveRequest(t, server, request, ListDraftNotesResponse{})

		assert(t, data.SuccessResponse.Message, "Draft notes fetched successfully")
		assert(t, data.SuccessResponse.Status, http.StatusOK)
	})
}
