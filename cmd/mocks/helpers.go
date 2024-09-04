package mocks

import (
	bytes "bytes"
	io "io"
	"net/http"
	"testing"

	gitlab "github.com/xanzy/go-gitlab"
)

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

type Returner interface {
	Return([]*gitlab.MergeRequest, *gitlab.Response) ([]*gitlab.MergeRequest, *gitlab.Response, error)
}
type Lister interface {
	ListProjectMergeRequests(string, *gitlab.ListProjectMergeRequestsOptions) Returner
}

type Blah interface {
	EXPECT() Lister
}

// Adds a handler to satisfy the withMrs middleware by returning an MR from that endpoint with the given ID */
func WithMr[T Blah](t *testing.T, m T) {
	options := gitlab.ListProjectMergeRequestsOptions{
		Scope:        gitlab.Ptr("all"),
		State:        gitlab.Ptr("opened"),
		SourceBranch: gitlab.Ptr(""),
	}

	m.EXPECT().ListProjectMergeRequests("", &options).Return([]*gitlab.MergeRequest{{IID: MergeId}}, makeResponse(http.StatusOK))
}

type MockAttachmentReader struct{}

func (mf MockAttachmentReader) ReadFile(path string) (io.Reader, error) {
	return bytes.NewReader([]byte{}), nil
}
