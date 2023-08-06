package main

import (
	"errors"
	"fmt"
	"io"
	"net/http"
)

const mrUrl = "%s/api/v4/projects/%s/merge_requests/%d"

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
		return nil, errors.New(fmt.Sprintf("Recieved non-200 response: %d", res.StatusCode))
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
		c.handleError(w, errors.New("Invalid request type"), "That request type is not allowed", http.StatusMethodNotAllowed)
		return
	}

	msg, err := c.Info()
	if err != nil {
		c.handleError(w, err, "Could not get info", http.StatusBadRequest)
		return
	}

	w.WriteHeader(http.StatusOK)
	w.Write(msg)
}
