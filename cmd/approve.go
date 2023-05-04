package main

import (
	"encoding/json"
	"fmt"
	"net/http"
)

func (c *Client) Approve() (string, error) {

	_, _, err := c.git.MergeRequestApprovals.ApproveMergeRequest(c.projectId, c.mergeId, nil, nil)

	if err != nil {
		return "", fmt.Errorf("Approving MR failed: %w", err)
	}

	return "Success! Approved MR.", nil
}

func ApproveHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	client := r.Context().Value("client").(Client)
	msg, err := client.Approve()
	if err != nil {
		errResp := map[string]string{"message": err.Error()}
		response, _ := json.MarshalIndent(errResp, "", "  ")
		w.WriteHeader(http.StatusInternalServerError)
		w.Write(response)
		return
	}

	w.WriteHeader(http.StatusOK)
	response := map[string]string{"message": msg}
	json.NewEncoder(w).Encode(response)
}
