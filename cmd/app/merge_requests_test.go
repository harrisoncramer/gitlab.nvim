package app

// import (
// 	"net/http"
// 	"testing"
//
// 	"github.com/xanzy/go-gitlab"
// 	mock_main "gitlab.com/harrisoncramer/gitlab.nvim/cmd/mocks"
// 	"go.uber.org/mock/gomock"
// )
//
// var testListMergeRequestsRequest = ListMergeRequestRequest{
// 	Label:    []string{},
// 	NotLabel: []string{},
// }
//
// func TestMergeRequestHandler(t *testing.T) {
// 	t.Run("Should fetch merge requests", func(t *testing.T) {
// 		client := mock_main.NewMockClient(t)
// 		mock_main.WithMr(t, client)
// 		client.EXPECT().ListProjectMergeRequests("", gomock.Any()).Return([]*gitlab.MergeRequest{
// 			{
// 				IID: 10,
// 			},
// 		}, makeResponse(http.StatusOK), nil)
//
// 		request := makeRequest(t, http.MethodPost, "/merge_requests", testListMergeRequestsRequest)
// 		server := CreateRouter(client)
// 		data := serveRequest(t, server, request, ListMergeRequestResponse{})
//
// 		assert(t, data.Message, "Merge requests fetched successfully")
// 		assert(t, data.Status, http.StatusOK)
// 	})
//
// 	t.Run("Should handle an error from Gitlab", func(t *testing.T) {
// 		client := mock_main.NewMockClient(t)
// 		mock_main.WithMr(t, client)
// 		client.EXPECT().ListProjectMergeRequests("", gomock.Any()).Return(nil, nil, errorFromGitlab)
//
// 		request := makeRequest(t, http.MethodPost, "/merge_requests", testListMergeRequestsRequest)
// 		server := CreateRouter(client)
// 		data := serveRequest(t, server, request, ErrorResponse{})
//
// 		assert(t, data.Message, "Failed to list merge requests")
// 		assert(t, data.Status, http.StatusInternalServerError)
// 	})
//
// 	t.Run("Should handle a non-200", func(t *testing.T) {
// 		client := mock_main.NewMockClient(t)
// 		mock_main.WithMr(t, client)
// 		client.EXPECT().ListProjectMergeRequests("", gomock.Any()).Return(nil, makeResponse(http.StatusSeeOther), nil)
//
// 		request := makeRequest(t, http.MethodPost, "/merge_requests", testListMergeRequestsRequest)
// 		server := CreateRouter(client)
// 		data := serveRequest(t, server, request, ErrorResponse{})
//
// 		assert(t, data.Message, "Failed to list merge requests")
// 		assert(t, data.Status, http.StatusSeeOther)
// 	})
//
// 	t.Run("Should handle not having any merge requests with 404", func(t *testing.T) {
// 		client := mock_main.NewMockClient(t)
// 		mock_main.WithMr(t, client)
// 		client.EXPECT().ListProjectMergeRequests("", gomock.Any()).Return([]*gitlab.MergeRequest{}, makeResponse(http.StatusOK), nil)
//
// 		request := makeRequest(t, http.MethodPost, "/merge_requests", testListMergeRequestsRequest)
// 		server := CreateRouter(client)
// 		data := serveRequest(t, server, request, ListMergeRequestResponse{})
//
// 		assert(t, data.Message, "No merge requests found")
// 		assert(t, data.Status, http.StatusNotFound)
// 	})
// }
