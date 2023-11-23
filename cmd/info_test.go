package main

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/xanzy/go-gitlab"
)

type FakeInfoFetcher struct{}

func (f FakeInfoFetcher) GetMergeRequest(pid interface{}, mergeRequest int, opt *gitlab.GetMergeRequestsOptions, options ...gitlab.RequestOptionFunc) (*gitlab.MergeRequest, *gitlab.Response, error) {
	return &gitlab.MergeRequest{}, &gitlab.Response{}, nil
}

func TestInfoHandler(t *testing.T) {
	request, err := http.NewRequest("GET", "/info", nil)
	if err != nil {
		t.Fatal(err)
	}

	recorder := httptest.NewRecorder()
	InfoHandler := FakeInfoFetcher{}
	client := gitlab.Client{}

	f := Middleware(&client, &ProjectInfo{}, InfoHandler)
	handler := http.HandlerFunc()
	handler.ServeHTTP(recorder, request)

}
