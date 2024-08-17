package mock_main

import (
	"net/http"
	"testing"

	gitlab "github.com/xanzy/go-gitlab"
	gomock "go.uber.org/mock/gomock"
)

type NoOp = []gitlab.RequestOptionFunc

func NewListMrOptions() *gitlab.ListProjectMergeRequestsOptions {
	return &gitlab.ListProjectMergeRequestsOptions{
		Scope:        gitlab.Ptr("all"),
		State:        gitlab.Ptr("opened"),
		SourceBranch: gitlab.Ptr(""),
	}
}

/* Make response makes a simple response value with the right status code */
func makeResponse(status int) *gitlab.Response {
	return &gitlab.Response{
		Response: &http.Response{
			StatusCode: status,
		},
	}
}

type MockOpts struct {
	MergeId int
}

func NewMockObj(t *testing.T) *MockClientInterface {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()
	mockObj := NewMockClientInterface(ctrl)
	return mockObj
}
