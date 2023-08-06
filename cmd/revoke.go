package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
)

func (c *Client) Revoke() (string, int, error) {

	res, err := c.git.MergeRequestApprovals.UnapproveMergeRequest(c.projectId, c.mergeId, nil, nil)

	if err != nil {
		return "", res.Response.StatusCode, fmt.Errorf("Revoking approval failed: %w", err)
	}

	return "Success! Revoked MR approval.", http.StatusOK, nil

}

func RevokeHandler(w http.ResponseWriter, r *http.Request) {
	c := r.Context().Value("client").(Client)
	w.Header().Set("Content-Type", "application/json")

	if r.Method != http.MethodPost {
		c.handleError(w, errors.New("Invalid request type"), "That request type is not allowed", http.StatusMethodNotAllowed)
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}

	msg, status, err := c.Revoke()

	if err != nil {
		c.handleError(w, err, "Could not revoke approval", http.StatusBadRequest)
		return
	}

	w.WriteHeader(status)
	response := SuccessResponse{
		Message: msg,
		Status:  http.StatusOK,
	}

	json.NewEncoder(w).Encode(response)
}
