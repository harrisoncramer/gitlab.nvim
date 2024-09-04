package app

import (
	"net/http"
	"testing"
	"time"

	"github.com/xanzy/go-gitlab"
	mock_main "gitlab.com/harrisoncramer/gitlab.nvim/cmd/mocks"
	"go.uber.org/mock/gomock"
)

var now = time.Now()
var newer = now.Add(time.Second * 100)

type Author struct {
	ID        int    `json:"id"`
	Username  string `json:"username"`
	Email     string `json:"email"`
	Name      string `json:"name"`
	State     string `json:"state"`
	AvatarURL string `json:"avatar_url"`
	WebURL    string `json:"web_url"`
}

var testListDiscussionsResponse = []*gitlab.Discussion{
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

func TestListDiscussionsHandler(t *testing.T) {
	t.Run("Returns sorted discussions", func(t *testing.T) {
		client := mock_main.NewMockClient(t)
		mock_main.WithMr(t, client)
		client.EXPECT().ListMergeRequestDiscussions("", mock_main.MergeId, gomock.Any()).Return(testListDiscussionsResponse, makeResponse(http.StatusOK), nil)
		client.EXPECT().ListMergeRequestAwardEmojiOnNote("", mock_main.MergeId, gomock.Any(), gomock.Any()).Return([]*gitlab.AwardEmoji{}, makeResponse(http.StatusOK), nil).Times(2)

		request := makeRequest(t, http.MethodPost, "/mr/discussions/list", DiscussionsRequest{})
		server := CreateRouter(client)
		data := serveRequest(t, server, request, DiscussionsResponse{})

		assert(t, data.SuccessResponse.Message, "Discussions retrieved")
		assert(t, data.SuccessResponse.Status, http.StatusOK)
		assert(t, data.Discussions[0].Notes[0].Author.Username, "hcramer2") /* Sorting applied */
		assert(t, data.Discussions[1].Notes[0].Author.Username, "hcramer")
	})

	t.Run("Uses blacklist to filter unwanted authors", func(t *testing.T) {
		client := mock_main.NewMockClient(t)
		mock_main.WithMr(t, client)
		client.EXPECT().ListMergeRequestDiscussions("", mock_main.MergeId, gomock.Any()).Return(testListDiscussionsResponse, makeResponse(http.StatusOK), nil)
		client.EXPECT().ListMergeRequestAwardEmojiOnNote("", mock_main.MergeId, gomock.Any(), gomock.Any()).Return([]*gitlab.AwardEmoji{}, makeResponse(http.StatusOK), nil).Times(2)

		request := makeRequest(t, http.MethodPost, "/mr/discussions/list", DiscussionsRequest{Blacklist: []string{"hcramer"}})
		server := CreateRouter(client)
		data := serveRequest(t, server, request, DiscussionsResponse{})

		assert(t, data.SuccessResponse.Message, "Discussions retrieved")
		assert(t, data.SuccessResponse.Status, http.StatusOK)
		assert(t, len(data.Discussions), 1)
		assert(t, data.Discussions[0].Notes[0].Author.Username, "hcramer2")
	})

	t.Run("Disallows non-POST method", func(t *testing.T) {
		client := mock_main.NewMockClient(t)
		mock_main.WithMr(t, client)

		request := makeRequest(t, http.MethodPut, "/mr/discussions/list", DiscussionsRequest{})
		server := CreateRouter(client)

		data := serveRequest(t, server, request, ErrorResponse{})
		checkBadMethod(t, *data, http.MethodPost)
	})

	t.Run("Handles errors from Gitlab client", func(t *testing.T) {
		client := mock_main.NewMockClient(t)
		mock_main.WithMr(t, client)
		client.EXPECT().ListMergeRequestDiscussions("", mock_main.MergeId, gomock.Any()).Return(nil, nil, errorFromGitlab)

		request := makeRequest(t, http.MethodPost, "/mr/discussions/list", DiscussionsRequest{})
		server := CreateRouter(client)

		data := serveRequest(t, server, request, ErrorResponse{})
		checkErrorFromGitlab(t, *data, "Could not list discussions")
	})

	t.Run("Handles non-200s from Gitlab client", func(t *testing.T) {
		client := mock_main.NewMockClient(t)
		mock_main.WithMr(t, client)
		client.EXPECT().ListMergeRequestDiscussions("", mock_main.MergeId, gomock.Any()).Return(nil, makeResponse(http.StatusSeeOther), nil)

		request := makeRequest(t, http.MethodPost, "/mr/discussions/list", DiscussionsRequest{})
		server := CreateRouter(client)

		data := serveRequest(t, server, request, ErrorResponse{})
		checkNon200(t, *data, "Could not list discussions", "/mr/discussions/list")
	})

	t.Run("Handles error from emoji service", func(t *testing.T) {
		client := mock_main.NewMockClient(t)
		mock_main.WithMr(t, client)
		client.EXPECT().ListMergeRequestDiscussions("", mock_main.MergeId, gomock.Any()).Return(testListDiscussionsResponse, makeResponse(http.StatusOK), nil)
		client.EXPECT().ListMergeRequestAwardEmojiOnNote("", mock_main.MergeId, gomock.Any(), gomock.Any()).Return(nil, nil, errorFromGitlab).Times(2)

		request := makeRequest(t, http.MethodPost, "/mr/discussions/list", DiscussionsRequest{})
		server := CreateRouter(client)
		data := serveRequest(t, server, request, ErrorResponse{})

		checkErrorFromGitlab(t, *data, "Could not fetch emojis")

	})
}
