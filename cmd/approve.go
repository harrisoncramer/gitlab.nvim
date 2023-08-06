package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
)

func (c *Client) Approve() (string, int, error) {

	_, res, err := c.git.MergeRequestApprovals.ApproveMergeRequest(c.projectId, c.mergeId, nil, nil)

	if err != nil {
		return "", res.Response.StatusCode, fmt.Errorf("Approving MR failed: %w", err)
	}

	return "Success! Approved MR.", http.StatusOK, nil
}

func ApproveHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	c := r.Context().Value("client").(Client)

	if r.Method != http.MethodPost {
		c.handleError(w, errors.New("Invalid request type"), "That request type is not allowed", http.StatusMethodNotAllowed)
		return
	}
	msg, status, err := c.Approve()

	if err != nil {
		c.handleError(w, err, "Could not approve MR", http.StatusBadRequest)
		return
	}

	/* TODO: Check for non-200 status codes */
	w.WriteHeader(status)
	response := SuccessResponse{
		Message: msg,
		Status:  http.StatusOK,
	}

	json.NewEncoder(w).Encode(response)
}
