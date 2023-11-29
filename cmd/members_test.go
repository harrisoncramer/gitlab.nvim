package main

import (
	"errors"
	"net/http"
	"testing"

	"github.com/xanzy/go-gitlab"
)

func listAllProjectMembers(pid interface{}, opt *gitlab.ListProjectMembersOptions, options ...gitlab.RequestOptionFunc) ([]*gitlab.ProjectMember, *gitlab.Response, error) {
	return []*gitlab.ProjectMember{}, makeResponse(http.StatusOK), nil
}

func listAllProjectMembersErr(pid interface{}, opt *gitlab.ListProjectMembersOptions, options ...gitlab.RequestOptionFunc) ([]*gitlab.ProjectMember, *gitlab.Response, error) {
	return nil, nil, errors.New("Some error from Gitlab")
}

func listAllProjectMembersNon200(pid interface{}, opt *gitlab.ListProjectMembersOptions, options ...gitlab.RequestOptionFunc) ([]*gitlab.ProjectMember, *gitlab.Response, error) {
	return nil, makeResponse(http.StatusSeeOther), nil
}

func TestMembersHandler(t *testing.T) {
	t.Run("Returns project members", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/project/members", nil)
		server := createServer(fakeClient{listAllProjectMembers: listAllProjectMembers}, &ProjectInfo{}, MockAttachmentReader{})
		data := serveRequest(t, server, request, ProjectMembersResponse{})
		assert(t, data.SuccessResponse.Message, "Project members retrieved")
		assert(t, data.SuccessResponse.Status, http.StatusOK)
	})

	t.Run("Disallows non-GET method", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/project/members", nil)
		server := createServer(fakeClient{listAllProjectMembers: listAllProjectMembers}, &ProjectInfo{}, MockAttachmentReader{})
		data := serveRequest(t, server, request, ErrorResponse{})
		checkBadMethod(t, *data, http.MethodGet)
	})

	t.Run("Handles errors from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/project/members", nil)
		server := createServer(fakeClient{listAllProjectMembers: listAllProjectMembersErr}, &ProjectInfo{}, MockAttachmentReader{})
		data := serveRequest(t, server, request, ErrorResponse{})
		checkErrorFromGitlab(t, *data, "Could not retrieve project members")
	})

	t.Run("Handles non-200s from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/project/members", nil)
		server := createServer(fakeClient{listAllProjectMembers: listAllProjectMembersNon200}, &ProjectInfo{}, MockAttachmentReader{})
		data := serveRequest(t, server, request, ErrorResponse{})
		checkNon200(t, *data, "Could not retrieve project members", "/project/members")
	})
}
