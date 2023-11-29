package main

import (
	"errors"
	"net/http"
	"testing"

	"github.com/xanzy/go-gitlab"
)

func updateAssignees(pid interface{}, mergeRequest int, opt *gitlab.UpdateMergeRequestOptions, options ...gitlab.RequestOptionFunc) (*gitlab.MergeRequest, *gitlab.Response, error) {
	return &gitlab.MergeRequest{}, makeResponse(http.StatusOK), nil
}

func updateAssigneesNon200(pid interface{}, mergeRequest int, opt *gitlab.UpdateMergeRequestOptions, options ...gitlab.RequestOptionFunc) (*gitlab.MergeRequest, *gitlab.Response, error) {
	return nil, makeResponse(http.StatusSeeOther), nil
}

func updateAssigneesErr(pid interface{}, mergeRequest int, opt *gitlab.UpdateMergeRequestOptions, options ...gitlab.RequestOptionFunc) (*gitlab.MergeRequest, *gitlab.Response, error) {
	return nil, nil, errors.New("Some error from Gitlab")
}

func TestAssigneeHandler(t *testing.T) {
	t.Run("Updates assignees", func(t *testing.T) {
		request := makeRequest(t, http.MethodPut, "/mr/assignee", AssigneeUpdateRequest{Ids: []int{1, 2}})
		server := createServer(fakeClient{updateMergeRequestFn: updateAssignees}, &ProjectInfo{}, MockAttachmentReader{})
		data := serveRequest(t, server, request, AssigneeUpdateResponse{})
		assert(t, data.SuccessResponse.Message, "Assignees updated")
		assert(t, data.SuccessResponse.Status, http.StatusOK)
	})

	t.Run("Disallows non-PUT method", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/mr/assignee", nil)
		server := createServer(fakeClient{updateMergeRequestFn: updateAssignees}, &ProjectInfo{}, MockAttachmentReader{})
		data := serveRequest(t, server, request, ErrorResponse{})
		assert(t, data.Status, http.StatusMethodNotAllowed)
		assert(t, data.Details, "Invalid request type")
		assert(t, data.Message, "Expected PUT")
	})

	t.Run("Handles errors from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodPut, "/mr/assignee", AssigneeUpdateRequest{Ids: []int{1, 2}})
		server := createServer(fakeClient{updateMergeRequestFn: updateAssigneesErr}, &ProjectInfo{}, MockAttachmentReader{})
		data := serveRequest(t, server, request, ErrorResponse{})
		assert(t, data.Status, http.StatusInternalServerError)
		assert(t, data.Message, "Could not modify merge request assignees")
		assert(t, data.Details, "Some error from Gitlab")
	})

	t.Run("Handles non-200s from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodPut, "/mr/assignee", AssigneeUpdateRequest{Ids: []int{1, 2}})
		server := createServer(fakeClient{updateMergeRequestFn: updateAssigneesNon200}, &ProjectInfo{}, MockAttachmentReader{})
		data := serveRequest(t, server, request, ErrorResponse{})
		assert(t, data.Status, http.StatusSeeOther)
		assert(t, data.Message, "Could not modify merge request assignees")
		assert(t, data.Details, "An error occurred on the /mr/assignee endpoint")
	})
}
