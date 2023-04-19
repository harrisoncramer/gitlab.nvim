package main

import (
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
)

const mrUrl = "https://gitlab.com/api/v4/projects/%s/merge_requests/%d"

func (c *Client) Info() error {

	req, err := http.NewRequest(http.MethodGet, fmt.Sprintf(mrUrl, c.projectId, c.mergeId), nil)

	if err != nil {
		return fmt.Errorf("Failed to build read request: %w", err)
	}

	req.Header.Set("PRIVATE-TOKEN", os.Getenv("GITLAB_TOKEN"))
	req.Header.Set("Content-Type", "application/json")

	res, err := http.DefaultClient.Do(req)

	if err != nil {
		return fmt.Errorf("Failed to make info request: %w", err)
	}

	defer res.Body.Close()

	if res.StatusCode < 200 || res.StatusCode >= 300 {
		return errors.New(fmt.Sprintf("Recieved non-200 response: %d", res.StatusCode))
	}

	body, err := io.ReadAll(res.Body)
	if err != nil {
		return fmt.Errorf("Failed to parse read response: %w", err)
	}

	/* This response is parsed into a table in our Lua code */
	fmt.Println(string(body))

	return nil
}
