package main

import (
	"encoding/json"
	"io"
	"net/http"

	"github.com/xanzy/go-gitlab"
)

type ReviewerUpdateRequest struct {
	Ids []int `json:"ids"`
}

type ReviewerUpdateResponse struct {
	SuccessResponse
	Reviewers []*gitlab.BasicUser `json:"reviewers"`
}

type ReviewersRequestResponse struct {
	SuccessResponse
	Reviewers []int `json:"reviewers"`
}

func ReviewersHandler(w http.ResponseWriter, r *http.Request) {
	c := r.Context().Value("client").(Client)
	w.Header().Set("Content-Type", "application/json")

	body, err := io.ReadAll(r.Body)
	if err != nil {
		c.handleError(w, err, "Could not read request body", http.StatusBadRequest)
		return
	}

	defer r.Body.Close()
	var reviewerUpdateRequest ReviewerUpdateRequest
	err = json.Unmarshal(body, &reviewerUpdateRequest)

	if err != nil {
		c.handleError(w, err, "Could not read JSON from request", http.StatusBadRequest)
		return
	}

	mr, res, err := c.git.MergeRequests.UpdateMergeRequest(c.projectId, c.mergeId, &gitlab.UpdateMergeRequestOptions{
		ReviewerIDs: &reviewerUpdateRequest.Ids,
	})

	if err != nil {
		c.handleError(w, err, "Could not modify merge request reviewers", http.StatusBadRequest)
		return
	}

	if res.StatusCode != http.StatusOK {
		c.handleError(w, err, "Could not modify merge request reviewers", http.StatusBadRequest)
		return
	}

	w.WriteHeader(http.StatusOK)

	response := ReviewerUpdateResponse{
		SuccessResponse: SuccessResponse{
			Message: "Reviewers updated",
			Status:  http.StatusOK,
		},
		Reviewers: mr.Reviewers,
	}

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		c.handleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}
}
