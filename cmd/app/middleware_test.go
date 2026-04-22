package app

import (
	"encoding/json"
	"net/http"
	"testing"

	"github.com/harrisoncramer/gitlab.nvim/cmd/app/git"
	gitlab "gitlab.com/gitlab-org/api/client-go"
)

type FakePayload struct {
	Foo string `json:"foo" validate:"required"`
}

type fakeHandler struct{}

// capturingMergeRequestLister records the options passed to ListProjectMergeRequests
// so tests can verify the filter logic in the withMr middleware.
type capturingMergeRequestLister struct {
	capturedOpts *gitlab.ListProjectMergeRequestsOptions
}

func (f *capturingMergeRequestLister) ListProjectMergeRequests(pid interface{}, opt *gitlab.ListProjectMergeRequestsOptions, options ...gitlab.RequestOptionFunc) ([]*gitlab.BasicMergeRequest, *gitlab.Response, error) {
	f.capturedOpts = opt
	return []*gitlab.BasicMergeRequest{{IID: 10}}, makeResponse(http.StatusOK), nil
}

func (f fakeHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	data := SuccessResponse{Message: "Some message"}
	j, _ := json.Marshal(data)
	w.Write(j) // nolint

}

func TestMethodMiddleware(t *testing.T) {
	t.Run("Fails a bad method", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/foo", nil)
		mw := withMethodCheck(http.MethodPost)
		handler := middleware(fakeHandler{}, mw)
		data, status := getFailData(t, handler, request)
		assert(t, data.Message, "Invalid request type")
		assert(t, data.Details, "Expected: POST")
		assert(t, status, http.StatusMethodNotAllowed)
	})
	t.Run("Fails bad method with multiple", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/foo", nil)
		mw := withMethodCheck(http.MethodPost, http.MethodPatch)
		handler := middleware(fakeHandler{}, mw)
		data, status := getFailData(t, handler, request)
		assert(t, data.Message, "Invalid request type")
		assert(t, data.Details, "Expected: POST; PATCH")
		assert(t, status, http.StatusMethodNotAllowed)
	})
	t.Run("Allows ok method through", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/foo", nil)
		mw := withMethodCheck(http.MethodGet)
		handler := middleware(fakeHandler{}, mw)
		data := getSuccessData(t, handler, request)
		assert(t, data.Message, "Some message")
	})
}

func TestWithMrMiddleware(t *testing.T) {
	t.Run("Loads an MR ID into the projectInfo", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/foo", nil)
		d := data{
			projectInfo: &ProjectInfo{},
			gitInfo:     &git.GitData{BranchName: "foo"},
		}
		mw := withMr(d, fakeMergeRequestLister{})
		handler := middleware(fakeHandler{}, mw)
		getSuccessData(t, handler, request)
		if d.projectInfo.MergeId != 10 {
			t.FailNow()
		}
	})
	t.Run("Handles when there are no MRs", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/foo", nil)
		d := data{
			projectInfo: &ProjectInfo{},
			gitInfo:     &git.GitData{BranchName: "foo"},
		}
		mw := withMr(d, fakeMergeRequestLister{emptyResponse: true})
		handler := middleware(fakeHandler{}, mw)
		data, status := getFailData(t, handler, request)
		assert(t, status, http.StatusNotFound)
		assert(t, data.Message, "No MRs Found")
		assert(t, data.Details, "branch 'foo' does not have any merge requests")
	})
	t.Run("Handles when there are too many MRs", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/foo", nil)
		d := data{
			projectInfo: &ProjectInfo{},
			gitInfo:     &git.GitData{BranchName: "foo"},
		}
		mw := withMr(d, fakeMergeRequestLister{multipleMrs: true})
		handler := middleware(fakeHandler{}, mw)
		data, status := getFailData(t, handler, request)
		assert(t, status, http.StatusBadRequest)
		assert(t, data.Message, "Multiple MRs found")
		assert(t, data.Details, "please call gitlab.choose_merge_request()")
	})
	t.Run("Filters by IIDs when ChosenMrIID is set", func(t *testing.T) {
		pluginOptions.ChosenMrIID = 42
		defer func() { pluginOptions.ChosenMrIID = 0 }()

		request := makeRequest(t, http.MethodGet, "/foo", nil)
		lister := &capturingMergeRequestLister{}
		d := data{
			projectInfo: &ProjectInfo{},
			gitInfo:     &git.GitData{BranchName: "foo"},
		}
		mw := withMr(d, lister)
		handler := middleware(fakeHandler{}, mw)
		getSuccessData(t, handler, request)

		assert(t, (*lister.capturedOpts.IIDs)[0], int64(42))
		assert(t, lister.capturedOpts.SourceBranch == nil, true)
	})
	t.Run("Filters by SourceBranch when ChosenMrIID is not set", func(t *testing.T) {
		pluginOptions.ChosenMrIID = 0

		request := makeRequest(t, http.MethodGet, "/foo", nil)
		lister := &capturingMergeRequestLister{}
		d := data{
			projectInfo: &ProjectInfo{},
			gitInfo:     &git.GitData{BranchName: "foo"},
		}
		mw := withMr(d, lister)
		handler := middleware(fakeHandler{}, mw)
		getSuccessData(t, handler, request)

		assert(t, *lister.capturedOpts.SourceBranch, "foo")
		assert(t, lister.capturedOpts.IIDs == nil, true)
	})
}

func TestValidatorMiddleware(t *testing.T) {
	t.Run("Should error with missing field", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/foo", FakePayload{}) // No Foo field
		data, status := getFailData(t, middleware(
			fakeHandler{},
			withPayloadValidation(methodToPayload{http.MethodPost: newPayload[FakePayload]}),
		), request)
		assert(t, data.Message, "Invalid payload")
		assert(t, data.Details, "Foo is required")
		assert(t, status, http.StatusBadRequest)
	})
	t.Run("Should allow valid payload through", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/foo", FakePayload{Foo: "Some payload"})
		data := getSuccessData(t, middleware(
			fakeHandler{},
			withPayloadValidation(methodToPayload{http.MethodPost: newPayload[FakePayload]}),
		), request)
		assert(t, data.Message, "Some message")
	})
}
