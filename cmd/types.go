package main

import (
	"io"

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
