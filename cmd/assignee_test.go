package main

import (
	"bytes"
	"encoding/json"
	"net/http"
	"testing"
)

func TestAssigneeHandler(t *testing.T) {
	t.Run("Returns normal information", func(t *testing.T) {
		body := AssigneeUpdateRequest{
			Ids: []int{1, 2},
		}

		b, err := json.Marshal(body)
		if err != nil {
			t.Fatal(err)
		}

		reader := bytes.NewReader(b)
		request := makeRequest(t, http.MethodPut, "/mr/assignee", reader)
		client := FakeHandlerClient{}
		data := serveRequest(t, AssigneesHandler, client, request, AssigneeUpdateResponse{})

		assert(t, data.SuccessResponse.Status, http.StatusOK)
		assert(t, data.SuccessResponse.Message, "Assignees updated")
	})

	t.Run("Disallows non-PUT methods", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/mr/assignee", nil)
		client := FakeHandlerClient{}
		data := serveRequest(t, AssigneesHandler, client, request, ErrorResponse{})

		assert(t, data.Status, http.StatusMethodNotAllowed)
		assert(t, data.Message, "Expected PUT")
		assert(t, data.Details, "Invalid request type")
	})

	t.Run("Handles errors from Gitlab client", func(t *testing.T) {
		body := AssigneeUpdateRequest{
			Ids: []int{1, 2},
		}

		b, err := json.Marshal(body)
		if err != nil {
			t.Fatal(err)
		}

		reader := bytes.NewReader(b)
		request := makeRequest(t, http.MethodPut, "/mr/assignee", reader)
		client := FakeHandlerClient{Error: "Some error from Gitlab"}
		data := serveRequest(t, AssigneesHandler, client, request, ErrorResponse{})
		assert(t, data.Status, http.StatusInternalServerError)
		assert(t, data.Message, "Could not modify merge request assignees")
		assert(t, data.Details, "Some error from Gitlab")
	})

	t.Run("Handles errors from Gitlab client", func(t *testing.T) {
		body := AssigneeUpdateRequest{
			Ids: []int{1, 2},
		}

		b, err := json.Marshal(body)
		if err != nil {
			t.Fatal(err)
		}

		reader := bytes.NewReader(b)
		request := makeRequest(t, http.MethodPut, "/mr/assignee", reader)
		client := FakeHandlerClient{Error: "Some error from Gitlab"}
		data := serveRequest(t, AssigneesHandler, client, request, ErrorResponse{})
		assert(t, data.Status, http.StatusInternalServerError)
		assert(t, data.Message, "Could not modify merge request assignees")
		assert(t, data.Details, "Some error from Gitlab")
	})

	t.Run("Handles non-200s from Gitlab client", func(t *testing.T) {
		body := AssigneeUpdateRequest{
			Ids: []int{1, 2},
		}

		b, err := json.Marshal(body)
		if err != nil {
			t.Fatal(err)
		}

		reader := bytes.NewReader(b)
		request := makeRequest(t, http.MethodPut, "/mr/assignee", reader)
		client := FakeHandlerClient{StatusCode: http.StatusSeeOther}
		data := serveRequest(t, AssigneesHandler, client, request, ErrorResponse{})

		assert(t, data.Status, http.StatusSeeOther)
		assert(t, data.Message, "Gitlab returned non-200 status")
		assert(t, data.Details, "An error occured on the /mr/assignee endpoint")
	})
}
