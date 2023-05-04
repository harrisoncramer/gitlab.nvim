package main

import (
	"encoding/json"
	"fmt"
	"net/http"
)

func (c *Client) Star() (string, error) {
	project, _, err := c.git.Projects.StarProject(c.projectId)
	if err != nil {
		return "", fmt.Errorf("Starring project failed: %w", err)
	}

	return fmt.Sprintf("Starred project %s successfully!", project.Name), nil

}

func StarHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	client := r.Context().Value("client").(Client)
	msg, err := client.Star()
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
