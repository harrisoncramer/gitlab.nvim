package main

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/xanzy/go-gitlab"
)

type GitLabClient struct {
	*gitlab.Client
	MergeRequests
}

type MergeRequests struct{}

func (m *MergeRequests) GetMergeRequest(projectID string, mergeID int, options *gitlab.GetMergeRequestsOptions) (*gitlab.MergeRequest, *gitlab.Response, error) {
	return &gitlab.MergeRequest{}, &gitlab.Response{}, nil
}

func TestInfo(t *testing.T) {
	request, err := http.NewRequest("GET", "/info", nil)
	if err != nil {
		t.Fatal(err)
	}

	ctx := context.WithValue(context.Background(), "client", &GitLabClient{})
	request = request.WithContext(ctx)

	recorder := httptest.NewRecorder()

	handler := http.HandlerFunc(InfoHandler)
	handler.ServeHTTP(recorder, request)
}
