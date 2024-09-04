package app

//
// import (
// 	"net/http"
// 	"testing"
//
// 	"github.com/xanzy/go-gitlab"
// 	mock_main "gitlab.com/harrisoncramer/gitlab.nvim/cmd/mocks"
// 	"go.uber.org/mock/gomock"
// )
//
// var updatePayload = AssigneeUpdateRequest{Ids: []int{1, 2}}
//
// func TestAssigneeHandler(t *testing.T) {
// 	t.Run("Updates assignees", func(t *testing.T) {
// 		client := mock_main.NewMockClient(t)
// 		mock_main.WithMr(t, client)
// 		client.EXPECT().UpdateMergeRequest("", mock_main.MergeId, gomock.Any()).Return(&gitlab.MergeRequest{}, makeResponse(http.StatusOK), nil)
//
// 		request := makeRequest(t, http.MethodPut, "/mr/assignee", updatePayload)
// 		server := CreateRouter(client)
// 		data := serveRequest(t, server, request, AssigneeUpdateResponse{})
//
// 		assert(t, data.SuccessResponse.Message, "Assignees updated")
// 		assert(t, data.SuccessResponse.Status, http.StatusOK)
// 	})
//
// 	t.Run("Disallows non-PUT method", func(t *testing.T) {
// 		client := mock_main.NewMockClient(t)
// 		mock_main.WithMr(t, client)
// 		client.EXPECT().UpdateMergeRequest("", mock_main.MergeId, gomock.Any()).Return(&gitlab.MergeRequest{}, makeResponse(http.StatusOK), nil)
//
// 		request := makeRequest(t, http.MethodPost, "/mr/assignee", nil)
// 		server := CreateRouter(client)
// 		data := serveRequest(t, server, request, ErrorResponse{})
//
// 		assert(t, data.Status, http.StatusMethodNotAllowed)
// 		assert(t, data.Details, "Invalid request type")
// 		assert(t, data.Message, "Expected PUT")
// 	})
//
// 	t.Run("Handles errors from Gitlab client", func(t *testing.T) {
// 		client := mock_main.NewMockClient(t)
// 		mock_main.WithMr(t, client)
// 		client.EXPECT().UpdateMergeRequest("", mock_main.MergeId, gomock.Any()).Return(nil, nil, errorFromGitlab)
//
// 		request := makeRequest(t, http.MethodPut, "/mr/assignee", updatePayload)
// 		server := CreateRouter(client)
// 		data := serveRequest(t, server, request, ErrorResponse{})
//
// 		assert(t, data.Status, http.StatusInternalServerError)
// 		assert(t, data.Message, "Could not modify merge request assignees")
// 		assert(t, data.Details, "Some error from Gitlab")
// 	})
//
// 	t.Run("Handles non-200s from Gitlab client", func(t *testing.T) {
// 		client := mock_main.NewMockClient(t)
// 		mock_main.WithMr(t, client)
// 		client.EXPECT().UpdateMergeRequest("", mock_main.MergeId, gomock.Any()).Return(nil, makeResponse(http.StatusSeeOther), nil)
//
// 		request := makeRequest(t, http.MethodPut, "/mr/assignee", updatePayload)
// 		server := CreateRouter(client)
// 		data := serveRequest(t, server, request, ErrorResponse{})
//
// 		assert(t, data.Status, http.StatusSeeOther)
// 		assert(t, data.Message, "Could not modify merge request assignees")
// 		assert(t, data.Details, "An error occurred on the /mr/assignee endpoint")
// 	})
// }
