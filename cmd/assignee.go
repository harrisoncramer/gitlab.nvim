package main

import (
	"encoding/json"
	"io"
	"net/http"

	"github.com/xanzy/go-gitlab"
)

type AssigneeUpdateRequest struct {
	Ids []int `json:"ids"`
}

type AssigneeUpdateResponse struct {
	SuccessResponse
	Assignees []*gitlab.BasicUser `json:"assignees"`
}

type AssigneesRequestResponse struct {
	SuccessResponse
	Assignees []int `json:"assignees"`
}

func AssigneesHandler(w http.ResponseWriter, r *http.Request) {
	c := r.Context().Value("client").(Client)
	w.Header().Set("Content-Type", "application/json")

	body, err := io.ReadAll(r.Body)
	if err != nil {
		c.handleError(w, err, "Could not read request body", http.StatusBadRequest)
		return
	}

	defer r.Body.Close()
	var assigneeUpdateRequest AssigneeUpdateRequest
	err = json.Unmarshal(body, &assigneeUpdateRequest)

	if err != nil {
		c.handleError(w, err, "Could not read JSON from request", http.StatusBadRequest)
		return
	}

	mr, res, err := c.git.MergeRequests.UpdateMergeRequest(c.projectId, c.mergeId, &gitlab.UpdateMergeRequestOptions{
		AssigneeIDs: &assigneeUpdateRequest.Ids,
	})

	if err != nil {
		c.handleError(w, err, "Could not modify merge request assignees", http.StatusBadRequest)
		return
	}

	if res.StatusCode != http.StatusOK {
		c.handleError(w, err, "Could not modify merge request assignees", http.StatusBadRequest)
		return
	}

	w.WriteHeader(http.StatusOK)

	response := AssigneeUpdateResponse{
		SuccessResponse: SuccessResponse{
			Message: "Assignees updated",
			Status:  http.StatusOK,
		},
		Assignees: mr.Assignees,
	}

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		c.handleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}
}
