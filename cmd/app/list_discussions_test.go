package app

import (
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/xanzy/go-gitlab"
)

type fakeDiscussionsLister struct {
	testBase
	badEmojiResponse bool
}

func (f fakeDiscussionsLister) ListMergeRequestDiscussions(pid interface{}, mergeRequest int, opt *gitlab.ListMergeRequestDiscussionsOptions, options ...gitlab.RequestOptionFunc) ([]*gitlab.Discussion, *gitlab.Response, error) {
	resp, err := f.handleGitlabError()
	if err != nil {
		return nil, nil, err
	}
	now := time.Now()
	newer := now.Add(time.Second * 100)

	type Author struct {
		ID        int    `json:"id"`
		Username  string `json:"username"`
		Email     string `json:"email"`
		Name      string `json:"name"`
		State     string `json:"state"`
		AvatarURL string `json:"avatar_url"`
		WebURL    string `json:"web_url"`
	}

	testListDiscussionsResponse := []*gitlab.Discussion{
		{Notes: []*gitlab.Note{{CreatedAt: &now, Type: "DiffNote", Author: Author{Username: "hcramer"}}}},
		{Notes: []*gitlab.Note{{CreatedAt: &newer, Type: "DiffNote", Author: Author{Username: "hcramer2"}}}},
	}
	return testListDiscussionsResponse, resp, err
}

func (f fakeDiscussionsLister) ListMergeRequestAwardEmojiOnNote(pid interface{}, mergeRequestIID int, noteID int, opt *gitlab.ListAwardEmojiOptions, options ...gitlab.RequestOptionFunc) ([]*gitlab.AwardEmoji, *gitlab.Response, error) {
	resp, err := f.handleGitlabError()
	if err != nil {
		return nil, nil, err
	}

	if f.badEmojiResponse {
		return nil, nil, errors.New("Some error from emoji service")
	}
	return []*gitlab.AwardEmoji{}, resp, err
}

func getDiscussionsList(t *testing.T, svc ServiceWithHandler, request *http.Request) DiscussionsResponse {
	res := httptest.NewRecorder()
	svc.handler(res, request)

	var data DiscussionsResponse
	err := json.Unmarshal(res.Body.Bytes(), &data)
	if err != nil {
		t.Error(err)
	}
	return data
}

func TestListDiscussions(t *testing.T) {
	t.Run("Returns sorted discussions", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/mr/discussions/list", DiscussionsRequest{})
		svc := discussionsListerService{emptyProjectData, fakeDiscussionsLister{}}
		data := getDiscussionsList(t, svc, request)
		assert(t, data.Message, "Discussions retrieved")
		assert(t, data.SuccessResponse.Status, http.StatusOK)
		assert(t, data.Discussions[0].Notes[0].Author.Username, "hcramer2") /* Sorting applied */
		assert(t, data.Discussions[1].Notes[0].Author.Username, "hcramer")
	})

	t.Run("Uses blacklist to filter unwanted authors", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/mr/discussions/list", DiscussionsRequest{Blacklist: []string{"hcramer"}})
		svc := discussionsListerService{emptyProjectData, fakeDiscussionsLister{}}
		data := getDiscussionsList(t, svc, request)
		assert(t, data.SuccessResponse.Message, "Discussions retrieved")
		assert(t, data.SuccessResponse.Status, http.StatusOK)
		assert(t, len(data.Discussions), 1)
		assert(t, data.Discussions[0].Notes[0].Author.Username, "hcramer2")
	})
	t.Run("Disallows non-GET methods", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/mr/discussions/list", DiscussionsRequest{})
		svc := discussionsListerService{emptyProjectData, fakeDiscussionsLister{}}
		data := getFailData(t, svc, request)
		checkBadMethod(t, data, http.MethodPost)
	})
	t.Run("Handles errors from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/mr/discussions/list", DiscussionsRequest{})
		svc := discussionsListerService{emptyProjectData, fakeDiscussionsLister{testBase: testBase{errFromGitlab: true}}}
		data := getFailData(t, svc, request)
		checkErrorFromGitlab(t, data, "Could not list discussions")
	})
	t.Run("Handles non-200s from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/mr/discussions/list", DiscussionsRequest{})
		svc := discussionsListerService{emptyProjectData, fakeDiscussionsLister{testBase: testBase{status: http.StatusSeeOther}}}
		data := getFailData(t, svc, request)
		checkNon200(t, data, "Could not list discussions", "/mr/discussions/list")
	})
	t.Run("Handles error from emoji service", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/mr/discussions/list", DiscussionsRequest{})
		svc := discussionsListerService{emptyProjectData, fakeDiscussionsLister{badEmojiResponse: true}}
		data := getFailData(t, svc, request)
		assert(t, data.Message, "Could not fetch emojis")
		assert(t, data.Details, "Some error from emoji service")
	})
}
