package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"

	"github.com/xanzy/go-gitlab"
)

const mrUrl = "%s/api/v4/projects/%s/merge_requests/%d"

type InfoResponse struct {
	SuccessResponse
	Info *gitlab.MergeRequest `json:"info"`
}

func (c *Client) Info() ([]byte, error) {

	url := fmt.Sprintf(mrUrl, c.gitlabInstance, c.projectId, c.mergeId)
	req, err := http.NewRequest(http.MethodGet, url, nil)

	if err != nil {
		return nil, fmt.Errorf("Failed to build read request: %w", err)
	}

	req.Header.Set("PRIVATE-TOKEN", c.authToken)
	req.Header.Set("Content-Type", "application/json")

	res, err := http.DefaultClient.Do(req)

	if err != nil {
		return nil, fmt.Errorf("Failed to make info request: %w", err)
	}

	defer res.Body.Close()

	if res.StatusCode < 200 || res.StatusCode >= 300 {
		return nil, fmt.Errorf("Recieved non-200 response: %d", res.StatusCode)
	}

	body, err := io.ReadAll(res.Body)
	if err != nil {
		return nil, fmt.Errorf("Failed to parse read response: %w", err)
	}

	/* This response is parsed into a table in our Lua code */
	return body, nil

}

func InfoHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	c := r.Context().Value("client").(Client)

	if r.Method != http.MethodGet {
		w.Header().Set("Allow", http.MethodGet)
		c.handleError(w, errors.New("Invalid request type"), "That request type is not allowed", http.StatusMethodNotAllowed)
		return
	}

	msg, err := c.Info()
	if err != nil {
		c.handleError(w, err, "Could not get project info and initialize gitlab.nvim plugin", http.StatusBadRequest)
		return
	}

	var mergeRequest *gitlab.MergeRequest
	err = json.Unmarshal(msg, &mergeRequest)
	if err != nil {
		c.handleError(w, err, "Could not unmarshal data from merge requests", http.StatusBadRequest)
		return
	}

	w.WriteHeader(http.StatusOK)
	response := InfoResponse{
		SuccessResponse: SuccessResponse{
			Message: "Merge requests retrieved",
			Status:  http.StatusOK,
		},
		Info: mergeRequest,
	}

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		c.handleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}
}
