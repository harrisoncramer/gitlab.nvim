package main

import (
	"encoding/json"
	"errors"
	"net/http"
)

func ApproveHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	c := r.Context().Value("client").(Client)

	if r.Method != http.MethodPost {
		c.handleError(w, errors.New("Invalid request type"), "That request type is not allowed", http.StatusMethodNotAllowed)
		return
	}

	_, res, err := c.git.MergeRequestApprovals.ApproveMergeRequest(c.projectId, c.mergeId, nil, nil)

	if err != nil {
		c.handleError(w, err, "Could not approve MR", http.StatusBadRequest)
		return
	}

	/* TODO: Check for non-200 status codes */
	w.WriteHeader(res.StatusCode)
	response := SuccessResponse{
		Message: "Success! Approved MR.",
		Status:  http.StatusOK,
	}

	json.NewEncoder(w).Encode(response)
}
