package main

import (
	"errors"
	"net/http"
	"testing"

	"github.com/xanzy/go-gitlab"
)

func createMrFn(pid interface{}, opt *gitlab.CreateMergeRequestOptions, options ...gitlab.RequestOptionFunc) (*gitlab.MergeRequest, *gitlab.Response, error) {
	return &gitlab.MergeRequest{}, makeResponse(http.StatusOK), nil
}

func createMrFnErr(pid interface{}, opt *gitlab.CreateMergeRequestOptions, options ...gitlab.RequestOptionFunc) (*gitlab.MergeRequest, *gitlab.Response, error) {
	return nil, nil, errors.New("Some error from Gitlab")
}

func createMrFnNon200(pid interface{}, opt *gitlab.CreateMergeRequestOptions, options ...gitlab.RequestOptionFunc) (*gitlab.MergeRequest, *gitlab.Response, error) {
	return nil, makeResponse(http.StatusSeeOther), nil
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

	t.Run("Disallows non-POST methods", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/create_mr", CreateMrRequest{})
		server, _ := createRouterAndApi(fakeClient{createMrFn: createMrFn})
		data := serveRequest(t, server, request, ErrorResponse{})
		checkBadMethod(t, *data, http.MethodPost)
	})

	t.Run("Handles errors from Gitlab client", func(t *testing.T) {
		body := CreateMrRequest{
			Title:        "Some title",
			Description:  "Some description",
			TargetBranch: "main",
		}
		request := makeRequest(t, http.MethodPost, "/create_mr", body)
		server, _ := createRouterAndApi(fakeClient{createMrFn: createMrFnErr})
		data := serveRequest(t, server, request, ErrorResponse{})
		checkErrorFromGitlab(t, *data, "Could not create MR")
	})

	t.Run("Handles non-200s from Gitlab client", func(t *testing.T) {
		body := CreateMrRequest{
			Title:        "Some title",
			Description:  "Some description",
			TargetBranch: "main",
		}
		request := makeRequest(t, http.MethodPost, "/create_mr", body)
		server, _ := createRouterAndApi(fakeClient{createMrFn: createMrFnNon200})
		data := serveRequest(t, server, request, ErrorResponse{})
		checkNon200(t, *data, "Could not create MR", "/create_mr")
	})

	t.Run("Handles missing titles", func(t *testing.T) {
		body := CreateMrRequest{
			Title:        "",
			Description:  "Some description",
			TargetBranch: "main",
		}
		request := makeRequest(t, http.MethodPost, "/create_mr", body)
		server, _ := createRouterAndApi(fakeClient{createMrFn: createMrFn})
		data := serveRequest(t, server, request, ErrorResponse{})
		assert(t, data.Status, http.StatusBadRequest)
		assert(t, data.Message, "Could not create MR")
		assert(t, data.Details, "Title cannot be empty")
	})

	t.Run("Handles missing target branch", func(t *testing.T) {
		body := CreateMrRequest{
			Title:        "Some title",
			Description:  "Some description",
			TargetBranch: "",
		}
		request := makeRequest(t, http.MethodPost, "/create_mr", body)
		server, _ := createRouterAndApi(fakeClient{createMrFn: createMrFn})
		data := serveRequest(t, server, request, ErrorResponse{})
		assert(t, data.Status, http.StatusBadRequest)
		assert(t, data.Message, "Could not create MR")
		assert(t, data.Details, "Target branch cannot be empty")
	})
}
