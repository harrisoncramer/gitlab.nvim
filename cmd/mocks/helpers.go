package mock_main

import (
	bytes "bytes"
	io "io"
	"net/http"
	"testing"

	gitlab "github.com/xanzy/go-gitlab"
	gomock "go.uber.org/mock/gomock"
)

type NoOp = []gitlab.RequestOptionFunc

var MergeId = 3

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

func NewMockClient(t *testing.T) *MockClientInterface {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()
	mockObj := NewMockClientInterface(ctrl)
	return mockObj
}

/** Adds a handler to satisfy the withMrs middleware by returning an MR from that endpoint with the given ID */
func WithMr(t *testing.T, m *MockClientInterface) *MockClientInterface {
	options := gitlab.ListProjectMergeRequestsOptions{
		Scope:        gitlab.Ptr("all"),
		State:        gitlab.Ptr("opened"),
		SourceBranch: gitlab.Ptr(""),
	}

	m.EXPECT().ListProjectMergeRequests("", &options).Return([]*gitlab.MergeRequest{{IID: MergeId}}, makeResponse(http.StatusOK), nil)

	return m
}

type MockAttachmentReader struct{}

func (mf MockAttachmentReader) ReadFile(path string) (io.Reader, error) {
	return bytes.NewReader([]byte{}), nil
}
