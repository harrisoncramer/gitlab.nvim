package main

import (
	"encoding/json"
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
	if r.Method != http.MethodPost {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	client := r.Context().Value("client").(Client)
	msg, status, err := client.Revoke()
	w.WriteHeader(status)

	if err != nil {
		response := ErrorResponse{
			Message: err.Error(),
			Status:  status,
		}
		json.NewEncoder(w).Encode(response)
		return
	}

	response := SuccessResponse{
		Message: msg,
		Status:  http.StatusOK,
	}

	json.NewEncoder(w).Encode(response)
}
