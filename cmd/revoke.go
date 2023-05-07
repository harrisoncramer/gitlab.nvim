package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
)

func (c *Client) Revoke() (string, error) {

	log.Println("Revoking")
	_, err := c.git.MergeRequestApprovals.UnapproveMergeRequest(c.projectId, c.mergeId, nil, nil)

	if err != nil {
		return "", fmt.Errorf("Revoking approval failed: %w", err)
	}

	return "Success! Revoked MR approval.", nil

}

func RevokeHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	client := r.Context().Value("client").(Client)
	msg, err := client.Revoke()
	if err != nil {
		errResp := map[string]string{"message": err.Error()}
		response, _ := json.Marshal(errResp)
		w.WriteHeader(http.StatusInternalServerError)
		w.Write(response)
		return
	}

	w.WriteHeader(http.StatusOK)
	response := map[string]string{"message": msg}
	json.NewEncoder(w).Encode(response)
}
