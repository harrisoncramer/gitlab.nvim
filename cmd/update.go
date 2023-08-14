package main

import (
	"encoding/json"
	"errors"
	"io"
	"log"
	"net/http"

	"github.com/xanzy/go-gitlab"
)

type UpdateRequest struct {
	Description string `json:"description"`
}

type UpdateResponse struct {
	SuccessResponse
	MergeRequest *gitlab.MergeRequest `json:"mr"`
}

func UpdateHandler(w http.ResponseWriter, r *http.Request) {
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
	var updateRequest UpdateRequest
	err = json.Unmarshal(body, &updateRequest)

	if err != nil {
		c.handleError(w, err, "Could not read JSON from request", http.StatusBadRequest)
		return
	}

	git, err := gitlab.NewClient(c.authToken)
	if err != nil {
		log.Fatalf("Failed to create client: %v", err)
	}

	mr, res, err := git.MergeRequests.UpdateMergeRequest(c.projectId, c.mergeId, &gitlab.UpdateMergeRequestOptions{Description: &updateRequest.Description})

	if err != nil {
		c.handleError(w, err, "Could not edit merge request", http.StatusBadRequest)
		return
	}

	if res.StatusCode != http.StatusOK {
		c.handleError(w, err, "Could not edit merge request", http.StatusBadRequest)
		return
	}

	w.WriteHeader(http.StatusOK)

	response := UpdateResponse{
		SuccessResponse: SuccessResponse{
			Message: "Merge request updated",
			Status:  http.StatusOK,
		},
		MergeRequest: mr,
	}

	json.NewEncoder(w).Encode(response)

}
