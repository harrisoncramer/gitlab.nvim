package main

import (
	"encoding/json"
	"io"
	"net/http"

	"github.com/xanzy/go-gitlab"
)

type ReviewerUpdateRequest struct {
	Id int `json:"id"`
}

type ReviewerUpdateResponse struct {
	SuccessResponse
	Reviewers []*gitlab.BasicUser `json:"reviewers"`
}

type ReviewersRequestResponse struct {
	SuccessResponse
	Reviewers []int `json:"reviewers"`
}

func ReviewerHandler(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodDelete:
		DeleteReviewer(w, r)
	case http.MethodPut:
		AddReviewer(w, r)
	default:
		w.WriteHeader(http.StatusMethodNotAllowed)
	}
}

func DeleteReviewer(w http.ResponseWriter, r *http.Request) {
	// c := r.Context().Value("client").(Client)
	// w.Header().Set("Content-Type", "application/json")
}

func AddReviewer(w http.ResponseWriter, r *http.Request) {
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

	if err != nil {
		c.handleError(w, err, "Could not convert ID of reviewer to integer", http.StatusBadRequest)
		return
	}

	reviewerIds := &[]int{reviewerUpdateRequest.Id}
	mr, res, err := c.git.MergeRequests.UpdateMergeRequest(c.projectId, c.mergeId, &gitlab.UpdateMergeRequestOptions{
		ReviewerIDs: reviewerIds,
	})

	if err != nil {
		c.handleError(w, err, "Could not edit merge request reviewer", http.StatusBadRequest)
		return
	}

	if res.StatusCode != http.StatusOK {
		c.handleError(w, err, "Could not edit merge request reviewer", http.StatusBadRequest)
		return
	}

	w.WriteHeader(http.StatusOK)

	response := ReviewerUpdateResponse{
		SuccessResponse: SuccessResponse{
			Message: "Reviewer updated",
			Status:  http.StatusOK,
		},
		Reviewers: mr.Reviewers,
	}

	json.NewEncoder(w).Encode(response)

}
