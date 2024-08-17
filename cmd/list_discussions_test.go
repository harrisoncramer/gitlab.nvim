package main

import (
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
	return nil, nil, errorFromGitlab
}

func listMergeRequestDiscussionsNon200(pid interface{}, mergeRequest int, opt *gitlab.ListMergeRequestDiscussionsOptions, options ...gitlab.RequestOptionFunc) ([]*gitlab.Discussion, *gitlab.Response, error) {
	return nil, makeResponse(http.StatusSeeOther), nil
}

func listMergeRequestAwardEmojiOnNote(pid interface{}, mr int, noteID int, opt *gitlab.ListAwardEmojiOptions, options ...gitlab.RequestOptionFunc) ([]*gitlab.AwardEmoji, *gitlab.Response, error) {
	return []*gitlab.AwardEmoji{}, makeResponse(http.StatusOK), nil
}

func listMergeRequestAwardEmojiOnNoteFailure(pid interface{}, mr int, noteID int, opt *gitlab.ListAwardEmojiOptions, options ...gitlab.RequestOptionFunc) ([]*gitlab.AwardEmoji, *gitlab.Response, error) {
	return nil, makeResponse(http.StatusBadRequest), errorFromGitlab
}

func TestListDiscussionsHandler(t *testing.T) {
	t.Run("Returns sorted discussions", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/mr/discussions/list", DiscussionsRequest{})
		server, _ := CreateRouterAndApi(fakeClient{listMergeRequestDiscussions: listMergeRequestDiscussions, listMergeRequestAwardEmojiOnNote: listMergeRequestAwardEmojiOnNote})
		data := serveRequest(t, server, request, DiscussionsResponse{})
		assert(t, data.SuccessResponse.Message, "Discussions retrieved")
		assert(t, data.SuccessResponse.Status, http.StatusOK)
		assert(t, data.Discussions[0].Notes[0].Author.Username, "hcramer2") /* Sorting applied */
		assert(t, data.Discussions[1].Notes[0].Author.Username, "hcramer")
	})

	t.Run("Uses blacklist to filter unwanted authors", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/mr/discussions/list", DiscussionsRequest{Blacklist: []string{"hcramer"}})
		server, _ := CreateRouterAndApi(fakeClient{listMergeRequestDiscussions: listMergeRequestDiscussions, listMergeRequestAwardEmojiOnNote: listMergeRequestAwardEmojiOnNote})
		data := serveRequest(t, server, request, DiscussionsResponse{})
		assert(t, data.SuccessResponse.Message, "Discussions retrieved")
		assert(t, data.SuccessResponse.Status, http.StatusOK)
		assert(t, len(data.Discussions), 1)
		assert(t, data.Discussions[0].Notes[0].Author.Username, "hcramer2")
	})

	t.Run("Disallows non-POST method", func(t *testing.T) {
		request := makeRequest(t, http.MethodPatch, "/mr/discussions/list", DiscussionsRequest{})
		server, _ := CreateRouterAndApi(fakeClient{listMergeRequestDiscussions: listMergeRequestDiscussions, listMergeRequestAwardEmojiOnNote: listMergeRequestAwardEmojiOnNote})
		data := serveRequest(t, server, request, ErrorResponse{})
		checkBadMethod(t, *data, http.MethodPost)
	})

	t.Run("Handles errors from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/mr/discussions/list", DiscussionsRequest{})
		server, _ := CreateRouterAndApi(fakeClient{listMergeRequestDiscussions: listMergeRequestDiscussionsErr, listMergeRequestAwardEmojiOnNote: listMergeRequestAwardEmojiOnNote})
		data := serveRequest(t, server, request, ErrorResponse{})
		checkErrorFromGitlab(t, *data, "Could not list discussions")
	})

	t.Run("Handles non-200s from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/mr/discussions/list", DiscussionsRequest{})
		server, _ := CreateRouterAndApi(fakeClient{listMergeRequestDiscussions: listMergeRequestDiscussionsNon200, listMergeRequestAwardEmojiOnNote: listMergeRequestAwardEmojiOnNote})
		data := serveRequest(t, server, request, ErrorResponse{})
		checkNon200(t, *data, "Could not list discussions", "/mr/discussions/list")
	})

	t.Run("Handles error from emoji service", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/mr/discussions/list", DiscussionsRequest{})
		server, _ := CreateRouterAndApi(fakeClient{listMergeRequestDiscussions: listMergeRequestDiscussions, listMergeRequestAwardEmojiOnNote: listMergeRequestAwardEmojiOnNoteFailure})
		data := serveRequest(t, server, request, ErrorResponse{})
		checkErrorFromGitlab(t, *data, "Could not fetch emojis")
	})
}
