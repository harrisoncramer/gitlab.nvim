package app

import (
	"net/http"
	"testing"

	"github.com/xanzy/go-gitlab"
)

type fakeApprover struct{}

func (f fakeApprover) ApproveMergeRequest(pid interface{}, mr int, opt *gitlab.ApproveMergeRequestOptions, options ...gitlab.RequestOptionFunc) (*gitlab.MergeRequestApprovals, *gitlab.Response, error) {
	return &gitlab.MergeRequestApprovals{}, makeResponse(http.StatusOK), nil
}

func TestApproveHandler(t *testing.T) {
	t.Run("Approves merge request", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/mr/approve", nil)
		client := fakeApprover{}
		svc := mergeRequestApproverService{emptyProjectData, client}
		data := getSuccessData(t, svc, request)
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
