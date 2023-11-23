package main

import (
	"bytes"
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

/* The Client struct embeds all the methods from Gitlab for the different services */
type Client struct {
	*gitlab.MergeRequestsService
	*gitlab.MergeRequestApprovalsService
	*gitlab.DiscussionsService
	*gitlab.ProjectsService
	*gitlab.ProjectMembersService
	*gitlab.JobsService
	*gitlab.PipelinesService
}

/* The HandlerClient interface implements all the methods that our handlers need */
type HandlerClient interface {
	UploadFile(pid interface{}, content io.Reader, filename string, options ...gitlab.RequestOptionFunc) (*gitlab.ProjectFile, *gitlab.Response, error)
	GetMergeRequest(pid interface{}, mr int, opt *gitlab.GetMergeRequestsOptions, options ...gitlab.RequestOptionFunc) (*gitlab.MergeRequest, *gitlab.Response, error)
	UpdateMergeRequest(pid interface{}, mr int, opt *gitlab.UpdateMergeRequestOptions, options ...gitlab.RequestOptionFunc) (*gitlab.MergeRequest, *gitlab.Response, error)
	GetMergeRequestDiffVersions(pid interface{}, mr int, opt *gitlab.GetMergeRequestDiffVersionsOptions, options ...gitlab.RequestOptionFunc) ([]*gitlab.MergeRequestDiffVersion, *gitlab.Response, error)
	ApproveMergeRequest(pid interface{}, mr int, opt *gitlab.ApproveMergeRequestOptions, options ...gitlab.RequestOptionFunc) (*gitlab.MergeRequestApprovals, *gitlab.Response, error)
	UnapproveMergeRequest(pid interface{}, mr int, options ...gitlab.RequestOptionFunc) (*gitlab.Response, error)
	ListMergeRequestDiscussions(pid interface{}, mergeRequest int, opt *gitlab.ListMergeRequestDiscussionsOptions, options ...gitlab.RequestOptionFunc) ([]*gitlab.Discussion, *gitlab.Response, error)
	ResolveMergeRequestDiscussion(pid interface{}, mergeRequest int, discussion string, opt *gitlab.ResolveMergeRequestDiscussionOptions, options ...gitlab.RequestOptionFunc) (*gitlab.Discussion, *gitlab.Response, error)
	CreateMergeRequestDiscussion(pid interface{}, mergeRequest int, opt *gitlab.CreateMergeRequestDiscussionOptions, options ...gitlab.RequestOptionFunc) (*gitlab.Discussion, *gitlab.Response, error)
	UpdateMergeRequestDiscussionNote(pid interface{}, mergeRequest int, discussion string, note int, opt *gitlab.UpdateMergeRequestDiscussionNoteOptions, options ...gitlab.RequestOptionFunc) (*gitlab.Note, *gitlab.Response, error)
	DeleteMergeRequestDiscussionNote(pid interface{}, mergeRequest int, discussion string, note int, options ...gitlab.RequestOptionFunc) (*gitlab.Response, error)
	AddMergeRequestDiscussionNote(pid interface{}, mergeRequest int, discussion string, opt *gitlab.AddMergeRequestDiscussionNoteOptions, options ...gitlab.RequestOptionFunc) (*gitlab.Note, *gitlab.Response, error)
	ListAllProjectMembers(pid interface{}, opt *gitlab.ListProjectMembersOptions, options ...gitlab.RequestOptionFunc) ([]*gitlab.ProjectMember, *gitlab.Response, error)
	RetryPipelineBuild(pid interface{}, pipeline int, options ...gitlab.RequestOptionFunc) (*gitlab.Pipeline, *gitlab.Response, error)
	ListPipelineJobs(pid interface{}, pipelineID int, opts *gitlab.ListJobsOptions, options ...gitlab.RequestOptionFunc) ([]*gitlab.Job, *gitlab.Response, error)
	GetTraceFile(pid interface{}, jobID int, options ...gitlab.RequestOptionFunc) (*bytes.Reader, *gitlab.Response, error)
}

/*
The FakeHandlerClient is used to create a fake gitlab client for testing our handlers, where the gitlab APIs are all mocked depending on what is provided during the variable initialization, so that we can simulate different responses from Gitlab
*/
type FakeHandlerClient struct {
	Title      string
	StatusCode int
	Error      string
}

func (f FakeHandlerClient) GetMergeRequest(pid interface{}, mergeRequest int, opt *gitlab.GetMergeRequestsOptions, options ...gitlab.RequestOptionFunc) (*gitlab.MergeRequest, *gitlab.Response, error) {
	if f.Error != "" {
		return nil, nil, errors.New(f.Error)
	}

	if f.StatusCode == 0 {
		f.StatusCode = 200
	}

	return &gitlab.MergeRequest{
			Title: f.Title,
		},
		&gitlab.Response{
			Response: &http.Response{
				StatusCode: f.StatusCode,
			},
		},
		nil
}

func (f FakeHandlerClient) UpdateMergeRequest(pid interface{}, mergeRequest int, opt *gitlab.UpdateMergeRequestOptions, options ...gitlab.RequestOptionFunc) (*gitlab.MergeRequest, *gitlab.Response, error) {
	return &gitlab.MergeRequest{}, &gitlab.Response{}, nil
}

func (f FakeHandlerClient) UploadFile(pid interface{}, content io.Reader, filename string, options ...gitlab.RequestOptionFunc) (*gitlab.ProjectFile, *gitlab.Response, error) {
	return &gitlab.ProjectFile{}, &gitlab.Response{}, nil
}

func (f FakeHandlerClient) GetMergeRequestDiffVersions(pid interface{}, mergeRequest int, opt *gitlab.GetMergeRequestDiffVersionsOptions, options ...gitlab.RequestOptionFunc) ([]*gitlab.MergeRequestDiffVersion, *gitlab.Response, error) {
	return []*gitlab.MergeRequestDiffVersion{}, &gitlab.Response{}, nil
}
