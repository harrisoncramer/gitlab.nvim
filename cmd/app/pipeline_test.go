package app

import (
	"net/http"
	"testing"

	"github.com/xanzy/go-gitlab"
)

type fakePipelineManager struct {
	testBase
}

func (f fakePipelineManager) ListProjectPipelines(pid interface{}, opt *gitlab.ListProjectPipelinesOptions, options ...gitlab.RequestOptionFunc) ([]*gitlab.PipelineInfo, *gitlab.Response, error) {
	resp, err := f.handleGitlabError()
	if err != nil {
		return nil, nil, err
	}
	return []*gitlab.PipelineInfo{{ID: 1234}}, resp, err
}

func (f fakePipelineManager) ListPipelineJobs(pid interface{}, pipelineID int, opts *gitlab.ListJobsOptions, options ...gitlab.RequestOptionFunc) ([]*gitlab.Job, *gitlab.Response, error) {
	resp, err := f.handleGitlabError()
	if err != nil {
		return nil, nil, err
	}
	return []*gitlab.Job{}, resp, err
}

func (f fakePipelineManager) RetryPipelineBuild(pid interface{}, pipeline int, options ...gitlab.RequestOptionFunc) (*gitlab.Pipeline, *gitlab.Response, error) {
	resp, err := f.handleGitlabError()
	if err != nil {
		return nil, nil, err
	}
	return &gitlab.Pipeline{}, resp, err
}

func TestPipelineGetter(t *testing.T) {
	t.Run("Gets all pipeline jobs", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/pipeline", nil)
		svc := pipelineService{testProjectData, fakePipelineManager{}, FakeGitManager{}}
		data := getSuccessData(t, svc, request)
		assert(t, data.Message, "Pipeline retrieved")
		assert(t, data.Status, http.StatusOK)
	})
	t.Run("Disallows non-GET, non-POST methods", func(t *testing.T) {
		request := makeRequest(t, http.MethodPatch, "/pipeline", nil)
		svc := pipelineService{testProjectData, fakePipelineManager{}, FakeGitManager{}}
		data := getFailData(t, svc, request)
		checkBadMethod(t, data, http.MethodGet, http.MethodPost)
	})
	t.Run("Handles errors from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/pipeline", nil)
		svc := pipelineService{testProjectData, fakePipelineManager{testBase{errFromGitlab: true}}, FakeGitManager{}}
		data := getFailData(t, svc, request)
		checkErrorFromGitlab(t, data, "Failed to get latest pipeline for some-branch branch")
	})
	t.Run("Handles non-200s from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/pipeline", nil)
		svc := pipelineService{testProjectData, fakePipelineManager{testBase: testBase{status: http.StatusSeeOther}}, FakeGitManager{}}
		data := getFailData(t, svc, request)
		assert(t, data.Message, "Failed to get latest pipeline for some-branch branch") // Expected, we treat this as an error
	})
}

func TestPipelineTrigger(t *testing.T) {
	t.Run("Retriggers pipeline", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/pipeline/trigger/3", nil)
		svc := pipelineService{testProjectData, fakePipelineManager{}, FakeGitManager{}}
		data := getSuccessData(t, svc, request)
		assert(t, data.Message, "Pipeline retriggered")
		assert(t, data.Status, http.StatusOK)
	})
	t.Run("Handles errors from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/pipeline/trigger/3", nil)
		svc := pipelineService{testProjectData, fakePipelineManager{testBase{errFromGitlab: true}}, FakeGitManager{}}
		data := getFailData(t, svc, request)
		checkErrorFromGitlab(t, data, "Could not retrigger pipeline")
	})
	t.Run("Handles non-200s from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/pipeline/trigger/3", nil)
		svc := pipelineService{testProjectData, fakePipelineManager{testBase: testBase{status: http.StatusSeeOther}}, FakeGitManager{}}
		data := getFailData(t, svc, request)
		checkNon200(t, data, "Could not retrigger pipeline", "/pipeline")
	})
}
