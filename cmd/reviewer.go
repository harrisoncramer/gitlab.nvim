package main

import (
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strconv"

	"github.com/xanzy/go-gitlab"
)

type ReviewerUpdateRequest struct {
	Id string `json:"id"`
}

type ReviewerUpdateResponse struct {
	SuccessResponse
	MergeRequest *gitlab.MergeRequest `json:"mr"`
}

func ReviewerHandler(w http.ResponseWriter, r *http.Request) {
	c := r.Context().Value("client").(Client)
	w.Header().Set("Content-Type", "application/json")
	if r.Method != http.MethodPut {
		c.handleError(w, errors.New("Invalid request type"), "That request type is not allowed", http.StatusMethodNotAllowed)
		return
	}

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

	id, err := strconv.Atoi(reviewerUpdateRequest.Id)
	if err != nil {
		c.handleError(w, err, "Could not convert ID of reviewer to integer", http.StatusBadRequest)
		return
	}

	reviewerIds := &[]int{id}
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
		MergeRequest: mr,
	}

	json.NewEncoder(w).Encode(response)

}
