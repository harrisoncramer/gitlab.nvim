package main

import (
	"errors"
	"io"
	"net/http"

	"github.com/xanzy/go-gitlab"
)

type ErrorResponse struct {
	Message string `json:"message"`
	Details string `json:"details"`
	Status  int    `json:"status"`
}

type SuccessResponse struct {
	Message string `json:"message"`
	Status  int    `json:"status"`
}

type MyClient struct {
	MergeRequests *gitlab.MergeRequestsService
	Projects      *gitlab.ProjectsService
}

func (c MyClient) GetMergeRequest(pid interface{}, mergeRequest int, opt *gitlab.GetMergeRequestsOptions, options ...gitlab.RequestOptionFunc) (*gitlab.MergeRequest, *gitlab.Response, error) {
	return c.MergeRequests.GetMergeRequest(pid, mergeRequest, opt, options...)
}

func (c MyClient) UpdateMergeRequest(pid interface{}, mergeRequest int, opt *gitlab.UpdateMergeRequestOptions, options ...gitlab.RequestOptionFunc) (*gitlab.MergeRequest, *gitlab.Response, error) {
	return c.MergeRequests.UpdateMergeRequest(pid, mergeRequest, opt, options...)
}

func (c MyClient) UploadFile(pid interface{}, content io.Reader, filename string, options ...gitlab.RequestOptionFunc) (*gitlab.ProjectFile, *gitlab.Response, error) {
	return c.Projects.UploadFile(pid, content, filename, options...)
}

/* For testing */
type FakeGitlabClient struct {
	MrTitle    string
	StatusCode int
	Error      string
}

func (f FakeGitlabClient) GetMergeRequest(pid interface{}, mergeRequest int, opt *gitlab.GetMergeRequestsOptions, options ...gitlab.RequestOptionFunc) (*gitlab.MergeRequest, *gitlab.Response, error) {
	if f.Error != "" {
		return nil, nil, errors.New(f.Error)
	}

	if f.StatusCode == 0 {
		f.StatusCode = 200
	}

	return &gitlab.MergeRequest{
			Title: f.MrTitle,
		},
		&gitlab.Response{
			Response: &http.Response{
				StatusCode: f.StatusCode,
			},
		},
		nil
}

func (f FakeGitlabClient) UpdateMergeRequest(pid interface{}, mergeRequest int, opt *gitlab.UpdateMergeRequestOptions, options ...gitlab.RequestOptionFunc) (*gitlab.MergeRequest, *gitlab.Response, error) {
	return &gitlab.MergeRequest{}, &gitlab.Response{}, nil
}
func (f FakeGitlabClient) UploadFile(pid interface{}, content io.Reader, filename string, options ...gitlab.RequestOptionFunc) (*gitlab.ProjectFile, *gitlab.Response, error) {
	return &gitlab.ProjectFile{}, &gitlab.Response{}, nil
}
