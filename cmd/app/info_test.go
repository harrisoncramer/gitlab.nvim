package app

// import (
// 	"net/http"
// 	"testing"
//
// 	"github.com/xanzy/go-gitlab"
// 	mock_main "gitlab.com/harrisoncramer/gitlab.nvim/cmd/mocks"
// )
//
// func TestInfoHandler(t *testing.T) {
// 	t.Run("Returns normal information", func(t *testing.T) {
// 		client := mock_main.NewMockClient(t)
// 		mock_main.WithMr(t, client)
// 		client.EXPECT().GetMergeRequest("", mock_main.MergeId, &gitlab.GetMergeRequestsOptions{}).Return(&gitlab.MergeRequest{}, makeResponse(http.StatusOK), nil)
//
// 		server := CreateRouter(client)
// 		request := makeRequest(t, http.MethodGet, "/mr/info", nil)
// 		data := serveRequest(t, server, request, InfoResponse{})
//
// 		assert(t, data.SuccessResponse.Message, "Merge requests retrieved")
// 		assert(t, data.SuccessResponse.Status, http.StatusOK)
// 	})
//
// 	t.Run("Disallows non-GET method", func(t *testing.T) {
// 		client := mock_main.NewMockClient(t)
// 		mock_main.WithMr(t, client)
//
// 		server := CreateRouter(client)
// 		request := makeRequest(t, http.MethodPost, "/mr/info", nil)
//
// 		data := serveRequest(t, server, request, ErrorResponse{})
// 		checkBadMethod(t, *data, http.MethodGet)
// 	})
//
// 	t.Run("Handles errors from Gitlab client", func(t *testing.T) {
// 		client := mock_main.NewMockClient(t)
// 		mock_main.WithMr(t, client)
// 		client.EXPECT().GetMergeRequest("", mock_main.MergeId, &gitlab.GetMergeRequestsOptions{}).Return(nil, nil, errorFromGitlab)
//
// 		server := CreateRouter(client)
// 		request := makeRequest(t, http.MethodGet, "/mr/info", nil)
//
// 		data := serveRequest(t, server, request, ErrorResponse{})
// 		checkErrorFromGitlab(t, *data, "Could not get project info")
// 	})
//
// 	t.Run("Handles non-200s from Gitlab client", func(t *testing.T) {
// 		client := mock_main.NewMockClient(t)
// 		mock_main.WithMr(t, client)
// 		client.EXPECT().GetMergeRequest("", mock_main.MergeId, &gitlab.GetMergeRequestsOptions{}).Return(nil, makeResponse(http.StatusSeeOther), nil)
//
// 		server := CreateRouter(client)
// 		request := makeRequest(t, http.MethodGet, "/mr/info", nil)
//
// 		data := serveRequest(t, server, request, ErrorResponse{})
// 		checkNon200(t, *data, "Could not get project info", "/mr/info")
// 	})
// }
