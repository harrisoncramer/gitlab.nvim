package app

import (
	"encoding/json"
	"net/http"
	"testing"

	"github.com/harrisoncramer/gitlab.nvim/cmd/app/git"
)

type fakeHandler struct{}

func (f fakeHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	data := SuccessResponse{Message: "Foo"}
	j, _ := json.Marshal(data)
	w.Write(j)
}

func TestMethodMiddleware(t *testing.T) {
	t.Run("Fails a bad method", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/foo", nil)
		mw := validateMethods(http.MethodPost)
		handler := middleware(fakeHandler{}, mw)
		data := getFailData(t, handler, request)
		assert(t, data.Message, "Invalid request type")
		assert(t, data.Details, "Expected: POST")
		assert(t, data.Status, http.StatusMethodNotAllowed)
	})
	t.Run("Fails bad method with multiple", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/foo", nil)
		mw := validateMethods(http.MethodPost, http.MethodPatch)
		handler := middleware(fakeHandler{}, mw)
		data := getFailData(t, handler, request)
		assert(t, data.Message, "Invalid request type")
		assert(t, data.Details, "Expected: POST; PATCH")
		assert(t, data.Status, http.StatusMethodNotAllowed)
	})
	t.Run("Allows ok method through", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/foo", nil)
		mw := validateMethods(http.MethodGet)
		handler := middleware(fakeHandler{}, mw)
		data := getSuccessData(t, handler, request)
		assert(t, data.Message, "Foo")
	})
}

func TestWithMrMiddleware(t *testing.T) {
	t.Run("Loads an MR ID", func(t *testing.T) {
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
}
