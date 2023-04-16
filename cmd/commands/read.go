package commands

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
)

/* Pulls down the MR description */
func Read(projectId string) error {
	mergeId := getCurrentMergeId()
	req, err := http.NewRequest(http.MethodGet, fmt.Sprintf(discussionsUrl, projectId, mergeId), nil)

	if err != nil {
		return err
	}

	req.Header.Set("PRIVATE-TOKEN", os.Getenv("GITLAB_TOKEN"))
	req.Header.Set("Content-Type", "application/json")

	res, err := http.DefaultClient.Do(req)

	if err != nil {
		return err
	}

	defer res.Body.Close()

	if res.StatusCode < 200 || res.StatusCode >= 300 {
		return errors.New(fmt.Sprintf("Recieved non-200 response: %d", res.StatusCode))
	}

	body, err := io.ReadAll(res.Body)
	if err != nil {
		return err
	}

	var response MergeRequest
	err = json.Unmarshal(body, &response)
	if err != nil {
		return err
	}

	fmt.Println(response.Description)

	return nil
}
