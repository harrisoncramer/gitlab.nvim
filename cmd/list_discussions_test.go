package main

import (
	"errors"
	"net/http"
	"testing"
	"time"

	"github.com/xanzy/go-gitlab"
)

func listMergeRequestDiscussions(pid interface{}, mergeRequest int, opt *gitlab.ListMergeRequestDiscussionsOptions, options ...gitlab.RequestOptionFunc) ([]*gitlab.Discussion, *gitlab.Response, error) {
	now := time.Now()
	newer := now.Add(time.Second * 100)
	discussions := []*gitlab.Discussion{
		{
			Notes: []*gitlab.Note{
				{
					CreatedAt: &now,
					Type:      "DiffNote",
					Author: Author{
						Username: "hcramer",
					},
				},
			},
		},
		{
			Notes: []*gitlab.Note{
				{
					CreatedAt: &newer,
					Type:      "DiffNote",
					Author: Author{
						Username: "hcramer2",
					},
				},
			},
		},
	}
	return discussions, makeResponse(http.StatusOK), nil
}

func listMergeRequestDiscussionsErr(pid interface{}, mergeRequest int, opt *gitlab.ListMergeRequestDiscussionsOptions, options ...gitlab.RequestOptionFunc) ([]*gitlab.Discussion, *gitlab.Response, error) {
	return nil, nil, errors.New("Some error from Gitlab")
}

func listMergeRequestDiscussionsNon200(pid interface{}, mergeRequest int, opt *gitlab.ListMergeRequestDiscussionsOptions, options ...gitlab.RequestOptionFunc) ([]*gitlab.Discussion, *gitlab.Response, error) {
	return nil, makeResponse(http.StatusSeeOther), nil
}

func TestListDiscussionsHandler(t *testing.T) {
	t.Run("Returns sorted discussions", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/discussions/list", DiscussionsRequest{})
		server, _ := createRouterAndApi(fakeClient{listMergeRequestDiscussions: listMergeRequestDiscussions})
		data := serveRequest(t, server, request, DiscussionsResponse{})
		assert(t, data.SuccessResponse.Message, "Discussions retrieved")
		assert(t, data.SuccessResponse.Status, http.StatusOK)
		assert(t, data.Discussions[0].Notes[0].Author.Username, "hcramer2") /* Sorting applied */
		assert(t, data.Discussions[1].Notes[0].Author.Username, "hcramer")
	})

	t.Run("Uses blacklist to filter unwanted authors", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/discussions/list", DiscussionsRequest{Blacklist: []string{"hcramer"}})
		server, _ := createRouterAndApi(fakeClient{listMergeRequestDiscussions: listMergeRequestDiscussions})
		data := serveRequest(t, server, request, DiscussionsResponse{})
		assert(t, data.SuccessResponse.Message, "Discussions retrieved")
		assert(t, data.SuccessResponse.Status, http.StatusOK)
		assert(t, len(data.Discussions), 1)
		assert(t, data.Discussions[0].Notes[0].Author.Username, "hcramer2")
	})

	t.Run("Disallows non-POST method", func(t *testing.T) {
		request := makeRequest(t, http.MethodPatch, "/discussions/list", DiscussionsRequest{})
		server, _ := createRouterAndApi(fakeClient{listMergeRequestDiscussions: listMergeRequestDiscussions})
		data := serveRequest(t, server, request, ErrorResponse{})
		checkBadMethod(t, *data, http.MethodPost)
	})

	t.Run("Handles errors from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/discussions/list", DiscussionsRequest{})
		server, _ := createRouterAndApi(fakeClient{listMergeRequestDiscussions: listMergeRequestDiscussionsErr})
		data := serveRequest(t, server, request, ErrorResponse{})
		checkErrorFromGitlab(t, *data, "Could not list discussions")
	})

	t.Run("Handles non-200s from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/discussions/list", DiscussionsRequest{})
		server, _ := createRouterAndApi(fakeClient{listMergeRequestDiscussions: listMergeRequestDiscussionsNon200})
		data := serveRequest(t, server, request, ErrorResponse{})
		checkNon200(t, *data, "Could not list discussions", "/discussions/list")
	})
}
