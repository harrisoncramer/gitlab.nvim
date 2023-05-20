package main

import (
	"encoding/json"
	"fmt"
	"net/http"

	"github.com/xanzy/go-gitlab"
)

func (c *Client) Star() (*gitlab.Project, int, error) {
	project, res, err := c.git.Projects.StarProject(c.projectId)
	if err != nil {
		return nil, res.Response.StatusCode, fmt.Errorf("Starring project failed: %w", err)
	}

	return project, http.StatusOK, nil

}

func StarHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	client := r.Context().Value("client").(Client)
	project, status, err := client.Star()

	w.Header().Set("Content-Type", "application/json")
	if err != nil {
		response := ErrorResponse{
			Message: err.Error(),
			Status:  status,
		}
		json.NewEncoder(w).Encode(response)
		return
	}

	response := SuccessResponse{
		Message: fmt.Sprintf("Starred project %s successfully!", project.Name),
		Status:  http.StatusOK,
	}

	json.NewEncoder(w).Encode(response)
}
