package commands

import (
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
)

/* Pulls down the MR description */
func Read(projectId string) error {

	mergeId := getCurrentMergeId()
	req, err := http.NewRequest(http.MethodGet, fmt.Sprintf(mrUrl, projectId, mergeId), nil)

	if err != nil {
		log.Fatalf("Failed to build read request: %s", err.Error())
	}
	if err != nil {
		return err
	}

	req.Header.Set("PRIVATE-TOKEN", os.Getenv("GITLAB_TOKEN"))
	req.Header.Set("Content-Type", "application/json")

	res, err := http.DefaultClient.Do(req)

	if err != nil {
		log.Fatalf("Failed to make read request: %s", err.Error())
	}

	defer res.Body.Close()

	if res.StatusCode < 200 || res.StatusCode >= 300 {
		return errors.New(fmt.Sprintf("Recieved non-200 response: %d", res.StatusCode))
	}

	body, err := io.ReadAll(res.Body)
	if err != nil {
		log.Fatalf("Failed to parse read response: %s", err.Error())
	}

	// var mr MergeRequest
	// err = json.Unmarshal(body, &mr)
	// if err != nil {
	// 	log.Fatalf("Failed to unmarshal read response data: %s", err.Error())
	// }

	fmt.Println(string(body))
	return nil
}
