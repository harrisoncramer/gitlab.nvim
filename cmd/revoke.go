package main

import (
	"encoding/json"
	"errors"
	"net/http"
)

func RevokeHandler(w http.ResponseWriter, r *http.Request) {
	c := r.Context().Value("client").(Client)
	w.Header().Set("Content-Type", "application/json")

	if r.Method != http.MethodPost {
		w.Header().Set("Allow", http.MethodPost)
		c.handleError(w, errors.New("Invalid request type"), "That request type is not allowed", http.StatusMethodNotAllowed)
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}

	res, err := c.git.MergeRequestApprovals.UnapproveMergeRequest(c.projectId, c.mergeId, nil, nil)

	if err != nil {
		c.handleError(w, err, "Could not revoke approval", http.StatusBadRequest)
		return
	}

	/* TODO: Check for non-200 status codes */
	w.WriteHeader(res.StatusCode)
	response := SuccessResponse{
		Message: "Success! Revoked MR approval.",
		Status:  http.StatusOK,
	}

	json.NewEncoder(w).Encode(response)
}
