package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
)

func (c *Client) Info() ([]byte, error) {
	const mrUrl = "%s/api/v4/projects/%s/merge_requests/%d"

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
	if r.Method != http.MethodGet {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	client := r.Context().Value("client").(Client)
	msg, err := client.Info()
	if err != nil {
		errResp := map[string]string{"message": err.Error()}
		response, _ := json.Marshal(errResp)
		w.WriteHeader(http.StatusInternalServerError)
		w.Write(response)
		return
	}

	w.WriteHeader(http.StatusOK)
	w.Write(msg)
}
