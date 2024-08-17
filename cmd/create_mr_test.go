package main

import (
	"net/http"
	"testing"

	"github.com/xanzy/go-gitlab"
	mock_main "gitlab.com/harrisoncramer/gitlab.nvim/cmd/mocks"
)

var testCreateMrRequestData = CreateMrRequest{
	Title:        "Some title",
	Description:  "Some description",
	TargetBranch: "main",
	DeleteBranch: false,
	Squash:       false,
}

var testCreateMrRequestOpts = gitlab.CreateMergeRequestOptions{
	Title:              &testCreateMrRequestData.Title,
	Description:        &testCreateMrRequestData.Description,
	TargetBranch:       &testCreateMrRequestData.TargetBranch,
	RemoveSourceBranch: &testCreateMrRequestData.DeleteBranch,
	Squash:             &testCreateMrRequestData.Squash,
	SourceBranch:       gitlab.Ptr(""),
}

func TestCreateMr(t *testing.T) {
	t.Run("Creates an MR", func(t *testing.T) {
		client := mock_main.NewMockClient(t)
		client.EXPECT().CreateMergeRequest("", &testCreateMrRequestOpts).Return(&gitlab.MergeRequest{}, makeResponse(http.StatusOK), nil)

		request := makeRequest(t, http.MethodPost, "/create_mr", testCreateMrRequestData)
		server, _ := CreateRouterAndApi(client)

		data := serveRequest(t, server, request, SuccessResponse{})
		assert(t, data.Message, "MR 'Some title' created")
		assert(t, data.Status, http.StatusOK)
	})

	t.Run("Disallows non-POST methods", func(t *testing.T) {
		client := mock_main.NewMockClient(t)
		client.EXPECT().CreateMergeRequest("", &testCreateMrRequestOpts).Return(nil, makeResponse(http.StatusSeeOther), nil)

		request := makeRequest(t, http.MethodPatch, "/create_mr", testCreateMrRequestData)
		server, _ := CreateRouterAndApi(client)
		data := serveRequest(t, server, request, ErrorResponse{})

		checkBadMethod(t, *data, http.MethodPost)
	})

	t.Run("Handles errors from Gitlab client", func(t *testing.T) {
		client := mock_main.NewMockClient(t)
		client.EXPECT().CreateMergeRequest("", &testCreateMrRequestOpts).Return(nil, nil, errorFromGitlab)

		request := makeRequest(t, http.MethodPost, "/create_mr", testCreateMrRequestData)
		server, _ := CreateRouterAndApi(client)
		data := serveRequest(t, server, request, ErrorResponse{})

		checkErrorFromGitlab(t, *data, "Could not create MR")
	})

	t.Run("Handles non-200s from Gitlab client", func(t *testing.T) {
		client := mock_main.NewMockClient(t)
		client.EXPECT().CreateMergeRequest("", &testCreateMrRequestOpts).Return(nil, makeResponse(http.StatusSeeOther), nil)

		request := makeRequest(t, http.MethodPost, "/create_mr", testCreateMrRequestData)
		server, _ := CreateRouterAndApi(client)
		data := serveRequest(t, server, request, ErrorResponse{})

		checkNon200(t, *data, "Could not create MR", "/create_mr")
	})

	t.Run("Handles missing titles", func(t *testing.T) {
		client := mock_main.NewMockClient(t)

		missingTitleRequest := testCreateMrRequestData
		missingTitleRequest.Title = ""
		missingTitleRequestOpts := testCreateMrRequestOpts
		missingTitleRequestOpts.Title = gitlab.Ptr("")

		client.EXPECT().CreateMergeRequest("", &missingTitleRequestOpts).Return(&gitlab.MergeRequest{}, makeResponse(http.StatusOK), nil)

		request := makeRequest(t, http.MethodPost, "/create_mr", missingTitleRequest)
		server, _ := CreateRouterAndApi(client)
		data := serveRequest(t, server, request, ErrorResponse{})

		assert(t, data.Status, http.StatusBadRequest)
		assert(t, data.Message, "Could not create MR")
		assert(t, data.Details, "Title cannot be empty")
	})

	t.Run("Handles missing target branch", func(t *testing.T) {
		client := mock_main.NewMockClient(t)

		missingTitleRequest := testCreateMrRequestData
		missingTitleRequest.TargetBranch = ""
		missingTitleRequestOpts := testCreateMrRequestOpts
		missingTitleRequestOpts.TargetBranch = gitlab.Ptr("")

		client.EXPECT().CreateMergeRequest("", &missingTitleRequestOpts).Return(&gitlab.MergeRequest{}, makeResponse(http.StatusOK), nil)

		request := makeRequest(t, http.MethodPost, "/create_mr", missingTitleRequest)
		server, _ := CreateRouterAndApi(client)
		data := serveRequest(t, server, request, ErrorResponse{})

		assert(t, data.Status, http.StatusBadRequest)
		assert(t, data.Message, "Could not create MR")
		assert(t, data.Details, "Target branch cannot be empty")
	})
}
