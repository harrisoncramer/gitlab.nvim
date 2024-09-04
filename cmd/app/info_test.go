package app

import (
	"net/http"
	"testing"

	"github.com/xanzy/go-gitlab"
)

type fakeMergeRequestGetter struct {
	testBase
}

func (f fakeMergeRequestGetter) GetMergeRequest(pid interface{}, mergeRequest int, opt *gitlab.GetMergeRequestsOptions, options ...gitlab.RequestOptionFunc) (*gitlab.MergeRequest, *gitlab.Response, error) {
	resp, err := f.handleGitlabError()
	if err != nil {
		return nil, nil, err
	}

	return &gitlab.MergeRequest{}, resp, err
}

func TestInfoHandler(t *testing.T) {
	t.Run("Returns normal information", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/mr/info", nil)
		svc := infoService{emptyProjectData, fakeMergeRequestGetter{}}
		data := getSuccessData(t, svc, request)
		assert(t, data.Message, "Merge requests retrieved")
		assert(t, data.Status, http.StatusOK)
	})
	t.Run("Disallows non-GET methods", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/mr/info", nil)
		svc := infoService{emptyProjectData, fakeMergeRequestGetter{}}
		data := getFailData(t, svc, request)
		checkBadMethod(t, data, http.MethodGet)
	})
	t.Run("Handles errors from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/mr/info", nil)
		svc := infoService{emptyProjectData, fakeMergeRequestGetter{testBase{errFromGitlab: true}}}
		data := getFailData(t, svc, request)
		checkErrorFromGitlab(t, data, "Could not get project info")
	})
	t.Run("Handles non-200s from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/mr/info", nil)
		svc := infoService{emptyProjectData, fakeMergeRequestGetter{testBase{status: http.StatusSeeOther}}}
		data := getFailData(t, svc, request)
		checkNon200(t, data, "Could not get project info", "/mr/info")
	})
}
