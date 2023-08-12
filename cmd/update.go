package main

import (
	"encoding/json"
	"errors"
	"io"
	"net/http"

	"github.com/xanzy/go-gitlab"
)

type UpdateRequest struct {
	Description string `json:"description"`
}

func UpdateHandler(w http.ResponseWriter, r *http.Request) {
	c := r.Context().Value("client").(Client)
	w.Header().Set("Content-Type", "application/json")
	if r.Method != http.MethodPost {
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

	mergeRequestOptions := gitlab.UpdateMergeRequestOptions{
		Description: gitlab.String(updateRequest.Description),
	}

	_, res, err := c.git.MergeRequests.UpdateMergeRequest(c.projectId, c.mergeId, &mergeRequestOptions)

	if err != nil {
		c.handleError(w, err, "Could not edit merge request", http.StatusBadRequest)
		return
	}

	if res.StatusCode != http.StatusOK {
		c.handleError(w, err, "Could not edit merge request", http.StatusBadRequest)
		return
	}

	/* TODO: Check for non 200 codes */
	w.WriteHeader(http.StatusOK)

	response := SuccessResponse{
		Message: "Merge request updated",
		Status:  http.StatusOK,
	}

	json.NewEncoder(w).Encode(response)

}
