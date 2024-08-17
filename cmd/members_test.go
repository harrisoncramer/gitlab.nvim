package main

import (
	"net/http"
	"testing"

	"github.com/xanzy/go-gitlab"
)

func listAllProjectMembers(pid interface{}, opt *gitlab.ListProjectMembersOptions, options ...gitlab.RequestOptionFunc) ([]*gitlab.ProjectMember, *gitlab.Response, error) {
	return []*gitlab.ProjectMember{}, makeResponse(http.StatusOK), nil
}

func listAllProjectMembersErr(pid interface{}, opt *gitlab.ListProjectMembersOptions, options ...gitlab.RequestOptionFunc) ([]*gitlab.ProjectMember, *gitlab.Response, error) {
	return nil, nil, errorFromGitlab
}

func listAllProjectMembersNon200(pid interface{}, opt *gitlab.ListProjectMembersOptions, options ...gitlab.RequestOptionFunc) ([]*gitlab.ProjectMember, *gitlab.Response, error) {
	return nil, makeResponse(http.StatusSeeOther), nil
}

func TestMembersHandler(t *testing.T) {
	t.Run("Returns project members", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/project/members", nil)
		server, _ := CreateRouterAndApi(fakeClient{listAllProjectMembers: listAllProjectMembers})
		data := serveRequest(t, server, request, ProjectMembersResponse{})
		assert(t, data.SuccessResponse.Message, "Project members retrieved")
		assert(t, data.SuccessResponse.Status, http.StatusOK)
	})

	t.Run("Disallows non-GET method", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/project/members", nil)
		server, _ := CreateRouterAndApi(fakeClient{listAllProjectMembers: listAllProjectMembers})
		data := serveRequest(t, server, request, ErrorResponse{})
		checkBadMethod(t, *data, http.MethodGet)
	})

	t.Run("Handles errors from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/project/members", nil)
		server, _ := CreateRouterAndApi(fakeClient{listAllProjectMembers: listAllProjectMembersErr})
		data := serveRequest(t, server, request, ErrorResponse{})
		checkErrorFromGitlab(t, *data, "Could not retrieve project members")
	})

	t.Run("Handles non-200s from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/project/members", nil)
		server, _ := CreateRouterAndApi(fakeClient{listAllProjectMembers: listAllProjectMembersNon200})
		data := serveRequest(t, server, request, ErrorResponse{})
		checkNon200(t, *data, "Could not retrieve project members", "/project/members")
	})
}
