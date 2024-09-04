package app

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/xanzy/go-gitlab"
	"gitlab.com/harrisoncramer/gitlab.nvim/cmd/app/git"
)

type fakeApprover struct{}

func (f fakeApprover) ApproveMergeRequest(pid interface{}, mr int, opt *gitlab.ApproveMergeRequestOptions, options ...gitlab.RequestOptionFunc) (*gitlab.MergeRequestApprovals, *gitlab.Response, error) {
	return &gitlab.MergeRequestApprovals{}, makeResponse(http.StatusOK), nil
}

func TestApproveHandler(t *testing.T) {
	t.Run("Approves merge request", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/mr/approve", nil)
		d := data{
			projectInfo: &ProjectInfo{},
			gitInfo:     &git.GitProjectInfo{},
		}
		client := fakeApprover{}
		svc := mergeRequestApproverService{d, client}
		res := httptest.NewRecorder()
		svc.handler(res, request)

		var data SuccessResponse
		err := json.Unmarshal(res.Body.Bytes(), &data)
		if err != nil {
			t.Error(err)
		}
		assert(t, data.Message, "Approved MR")
		assert(t, data.Status, http.StatusOK)
	})

	// t.Run("Disallows non-POST method", func(t *testing.T) {
	// 	client := mocks.NewMockClient(t)
	// 	mocks.WithMr(t, client)
	// 	client.EXPECT().ApproveMergeRequest("", mocks.MergeId, nil, nil).Return(&gitlab.MergeRequestApprovals{}, makeResponse(http.StatusOK), nil)
	//
	// 	request := makeRequest(t, http.MethodPut, "/mr/approve", nil)
	// 	server := CreateRouter(client)
	// 	data := serveRequest(t, server, request, ErrorResponse{})
	// 	checkBadMethod(t, *data, http.MethodPost)
	// })
	//
	// t.Run("Handles errors from Gitlab client", func(t *testing.T) {
	// 	client := mocks.NewMockClient(t)
	// 	mocks.WithMr(t, client)
	// 	client.EXPECT().ApproveMergeRequest("", mocks.MergeId, nil, nil).Return(nil, nil, errorFromGitlab)
	//
	// 	request := makeRequest(t, http.MethodPost, "/mr/approve", nil)
	// 	server := CreateRouter(client)
	// 	data := serveRequest(t, server, request, ErrorResponse{})
	//
	// 	checkErrorFromGitlab(t, *data, "Could not approve merge request")
	// })
	//
	// t.Run("Handles non-200s from Gitlab client", func(t *testing.T) {
	// 	client := mocks.NewMockClient(t)
	// 	mocks.WithMr(t, client)
	// 	client.EXPECT().ApproveMergeRequest("", mocks.MergeId, nil, nil).Return(nil, makeResponse(http.StatusSeeOther), nil)
	//
	// 	request := makeRequest(t, http.MethodPost, "/mr/approve", nil)
	// 	server := CreateRouter(client)
	// 	data := serveRequest(t, server, request, ErrorResponse{})
	//
	// 	checkNon200(t, *data, "Could not approve merge request", "/mr/approve")
	// })
}
