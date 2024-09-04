package app

// import (
// 	"fmt"
// 	"net/http"
// 	"testing"
//
// 	"github.com/xanzy/go-gitlab"
// 	mock_main "gitlab.com/harrisoncramer/gitlab.nvim/cmd/mocks"
// 	"go.uber.org/mock/gomock"
// )
//
// var testPipelineId = 12435
// var testPipelineCommit = "abc123"
// var fakeProjectPipelines = []*gitlab.PipelineInfo{{ID: testPipelineId}}
//
// /* This helps us stub out git interactions that the server would normally run in the project directory */
// func withGitInfo(a *Api) error {
// 	a.GitInfo.GetLatestCommitOnRemote = func(remote string, branchName string) (string, error) {
// 		return testPipelineCommit, nil
// 	}
// 	a.GitInfo.BranchName = "some-feature"
// 	return nil
// }
//
// func TestPipelineHandler(t *testing.T) {
// 	t.Run("Gets all pipeline jobs", func(t *testing.T) {
// 		client := mock_main.NewMockClient(t)
// 		client.EXPECT().ListProjectPipelines("", gomock.Any()).Return(fakeProjectPipelines, makeResponse(http.StatusOK), nil)
// 		client.EXPECT().ListPipelineJobs("", testPipelineId, &gitlab.ListJobsOptions{}).Return([]*gitlab.Job{}, makeResponse(http.StatusOK), nil)
//
// 		request := makeRequest(t, http.MethodGet, "/pipeline", nil)
// 		server := CreateRouter(client, withGitInfo)
// 		data := serveRequest(t, server, request, GetPipelineAndJobsResponse{})
//
// 		assert(t, data.SuccessResponse.Message, "Pipeline retrieved")
// 		assert(t, data.SuccessResponse.Status, http.StatusOK)
// 	})
//
// 	t.Run("Disallows non-GET, non-POST methods", func(t *testing.T) {
// 		client := mock_main.NewMockClient(t)
// 		request := makeRequest(t, http.MethodPatch, "/pipeline", nil)
// 		server := CreateRouter(client, withGitInfo)
//
// 		data := serveRequest(t, server, request, ErrorResponse{})
// 		checkBadMethod(t, *data, http.MethodGet, http.MethodPost)
// 	})
//
// 	t.Run("Handles errors from Gitlab client", func(t *testing.T) {
// 		client := mock_main.NewMockClient(t)
// 		client.EXPECT().ListProjectPipelines("", gomock.Any()).Return(fakeProjectPipelines, makeResponse(http.StatusOK), nil)
// 		client.EXPECT().ListPipelineJobs("", testPipelineId, &gitlab.ListJobsOptions{}).Return(nil, nil, errorFromGitlab)
//
// 		request := makeRequest(t, http.MethodGet, "/pipeline", nil)
// 		server := CreateRouter(client, withGitInfo)
//
// 		data := serveRequest(t, server, request, ErrorResponse{})
// 		checkErrorFromGitlab(t, *data, "Could not get pipeline jobs")
// 	})
//
// 	t.Run("Handles non-200s from Gitlab client", func(t *testing.T) {
// 		client := mock_main.NewMockClient(t)
// 		client.EXPECT().ListProjectPipelines("", gomock.Any()).Return(fakeProjectPipelines, makeResponse(http.StatusOK), nil)
// 		client.EXPECT().ListPipelineJobs("", testPipelineId, &gitlab.ListJobsOptions{}).Return(nil, makeResponse(http.StatusSeeOther), nil)
//
// 		request := makeRequest(t, http.MethodGet, "/pipeline", nil)
// 		server := CreateRouter(client, withGitInfo)
//
// 		data := serveRequest(t, server, request, ErrorResponse{})
// 		checkNon200(t, *data, "Could not get pipeline jobs", "/pipeline")
// 	})
//
// 	t.Run("Retriggers pipeline", func(t *testing.T) {
// 		client := mock_main.NewMockClient(t)
// 		client.EXPECT().RetryPipelineBuild("", testPipelineId).Return(&gitlab.Pipeline{}, makeResponse(http.StatusOK), nil)
//
// 		request := makeRequest(t, http.MethodPost, fmt.Sprintf("/pipeline/trigger/%d", testPipelineId), nil)
// 		server := CreateRouter(client, withGitInfo)
//
// 		data := serveRequest(t, server, request, GetPipelineAndJobsResponse{})
// 		assert(t, data.SuccessResponse.Message, "Pipeline retriggered")
// 		assert(t, data.SuccessResponse.Status, http.StatusOK)
// 	})
//
// 	t.Run("Handles non-200s from Gitlab client on retrigger", func(t *testing.T) {
// 		client := mock_main.NewMockClient(t)
// 		client.EXPECT().RetryPipelineBuild("", testPipelineId).Return(nil, makeResponse(http.StatusSeeOther), nil)
//
// 		request := makeRequest(t, http.MethodPost, fmt.Sprintf("/pipeline/trigger/%d", testPipelineId), nil)
// 		server := CreateRouter(client, withGitInfo)
//
// 		data := serveRequest(t, server, request, ErrorResponse{})
// 		checkNon200(t, *data, "Could not retrigger pipeline", "/pipeline")
// 	})
//
// 	t.Run("Handles error from Gitlab client on retrigger", func(t *testing.T) {
// 		client := mock_main.NewMockClient(t)
// 		client.EXPECT().RetryPipelineBuild("", testPipelineId).Return(nil, nil, errorFromGitlab)
//
// 		request := makeRequest(t, http.MethodPost, fmt.Sprintf("/pipeline/trigger/%d", testPipelineId), nil)
// 		server := CreateRouter(client, withGitInfo)
//
// 		data := serveRequest(t, server, request, ErrorResponse{})
// 		checkErrorFromGitlab(t, *data, "Could not retrigger pipeline")
// 	})
// }
