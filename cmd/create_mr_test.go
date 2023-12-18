package main

import (
	"net/http"
	"testing"

	"github.com/xanzy/go-gitlab"
)

func createMrFn(pid interface{}, opt *gitlab.CreateMergeRequestOptions, options ...gitlab.RequestOptionFunc) (*gitlab.MergeRequest, *gitlab.Response, error) {
	return &gitlab.MergeRequest{}, makeResponse(http.StatusOK), nil
}

func TestCreateMr(t *testing.T) {
	t.Run("Creates an MR", func(t *testing.T) {

		body := CreateMrRequest{
			Title:        "Some title",
			Description:  "Some description",
			TargetBranch: "main",
		}

		request := makeRequest(t, http.MethodPost, "/create_mr", body)
		server, _ := createRouterAndApi(fakeClient{createMrFn: createMrFn})
		data := serveRequest(t, server, request, SuccessResponse{})
		assert(t, data.Message, "MR 'Some title' created")
		assert(t, data.Status, http.StatusOK)
	})
}
