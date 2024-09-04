package app

// var testPostDraftNoteRequestData = PostDraftNoteRequest{
// 	Comment: "Some comment",
// }
//
// var testUpdateDraftNoteRequest = UpdateDraftNoteRequest{
// 	Note: "Some new note",
// }
//
// var testDraftNotePublishRequest = DraftNotePublishRequest{
// 	Note:       3,
// 	PublishAll: false,
// }
//
// func TestListDraftNotes(t *testing.T) {
// 	t.Run("Lists all draft notes", func(t *testing.T) {
// 		client := mock_main.NewMockClient(t)
// 		mock_main.WithMr(t, client)
// 		client.EXPECT().ListDraftNotes("", mock_main.MergeId, gomock.Any()).Return([]*gitlab.DraftNote{}, makeResponse(http.StatusOK), nil)
//
// 		request := makeRequest(t, http.MethodGet, "/mr/draft_notes/", nil)
// 		server := CreateRouter(client)
// 		data := serveRequest(t, server, request, ListDraftNotesResponse{})
//
// 		assert(t, data.SuccessResponse.Message, "Draft notes fetched successfully")
// 		assert(t, data.SuccessResponse.Status, http.StatusOK)
// 	})
//
// 	t.Run("Handles error", func(t *testing.T) {
// 		client := mock_main.NewMockClient(t)
// 		mock_main.WithMr(t, client)
// 		client.EXPECT().ListDraftNotes("", mock_main.MergeId, gomock.Any()).Return(nil, nil, errorFromGitlab)
//
// 		request := makeRequest(t, http.MethodGet, "/mr/draft_notes/", nil)
// 		server := CreateRouter(client)
// 		data := serveRequest(t, server, request, ErrorResponse{})
//
// 		assert(t, data.Message, "Could not get draft notes")
// 		assert(t, data.Status, http.StatusInternalServerError)
// 		assert(t, data.Details, errorFromGitlab.Error())
// 	})
// }
//
// func TestPostDraftNote(t *testing.T) {
// 	t.Run("Posts new draft note", func(t *testing.T) {
// 		client := mock_main.NewMockClient(t)
// 		mock_main.WithMr(t, client)
// 		client.EXPECT().CreateDraftNote("", mock_main.MergeId, gomock.Any()).Return(&gitlab.DraftNote{}, makeResponse(http.StatusOK), nil)
//
// 		request := makeRequest(t, http.MethodPost, "/mr/draft_notes/", testPostDraftNoteRequestData)
// 		server := CreateRouter(client)
// 		data := serveRequest(t, server, request, DraftNoteResponse{})
//
// 		assert(t, data.SuccessResponse.Message, "Draft note created successfully")
// 		assert(t, data.SuccessResponse.Status, http.StatusOK)
// 	})
//
// 	t.Run("Handles errors on draft note creation", func(t *testing.T) {
// 		client := mock_main.NewMockClient(t)
// 		mock_main.WithMr(t, client)
// 		client.EXPECT().CreateDraftNote("", mock_main.MergeId, gomock.Any()).Return(nil, nil, errorFromGitlab)
//
// 		request := makeRequest(t, http.MethodPost, "/mr/draft_notes/", testPostDraftNoteRequestData)
// 		server := CreateRouter(client)
// 		data := serveRequest(t, server, request, ErrorResponse{})
//
// 		assert(t, data.Message, "Could not create draft note")
// 		assert(t, data.Status, http.StatusInternalServerError)
// 		assert(t, data.Details, errorFromGitlab.Error())
// 	})
// }
//
// func TestDeleteDraftNote(t *testing.T) {
// 	t.Run("Deletes draft note", func(t *testing.T) {
// 		client := mock_main.NewMockClient(t)
// 		mock_main.WithMr(t, client)
// 		urlId := 10
// 		client.EXPECT().DeleteDraftNote("", mock_main.MergeId, urlId).Return(makeResponse(http.StatusOK), nil)
//
// 		request := makeRequest(t, http.MethodDelete, fmt.Sprintf("/mr/draft_notes/%d", urlId), nil)
// 		server := CreateRouter(client)
// 		data := serveRequest(t, server, request, DraftNoteResponse{})
//
// 		assert(t, data.SuccessResponse.Message, "Draft note deleted")
// 		assert(t, data.SuccessResponse.Status, http.StatusOK)
// 	})
//
// 	t.Run("Handles error", func(t *testing.T) {
// 		client := mock_main.NewMockClient(t)
// 		mock_main.WithMr(t, client)
// 		urlId := 10
// 		client.EXPECT().DeleteDraftNote("", mock_main.MergeId, urlId).Return(nil, errorFromGitlab)
//
// 		request := makeRequest(t, http.MethodDelete, fmt.Sprintf("/mr/draft_notes/%d", urlId), nil)
// 		server := CreateRouter(client)
// 		data := serveRequest(t, server, request, ErrorResponse{})
//
// 		assert(t, data.Message, "Could not delete draft note")
// 		assert(t, data.Status, http.StatusInternalServerError)
// 		assert(t, data.Details, errorFromGitlab.Error())
// 	})
//
// 	t.Run("Handles bad ID", func(t *testing.T) {
// 		client := mock_main.NewMockClient(t)
// 		mock_main.WithMr(t, client)
// 		urlId := "abc"
//
// 		request := makeRequest(t, http.MethodDelete, fmt.Sprintf("/mr/draft_notes/%s", urlId), nil)
// 		server := CreateRouter(client)
// 		data := serveRequest(t, server, request, ErrorResponse{})
//
// 		assert(t, data.Message, "Could not parse draft note ID")
// 		assert(t, data.Status, http.StatusBadRequest)
// 	})
// }
//
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
