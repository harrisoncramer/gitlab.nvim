package commands

import (
	"encoding/json"
	"io/ioutil"
	"log"
	"net/http"
	"os/exec"
	"strings"
)

type MergeRequest struct {
	ID           int    `json:"id"`
	IID          int    `json:"iid"`
	ProjectID    int    `json:"project_id"`
	Title        string `json:"title"`
	Description  string `json:"description"`
	State        string `json:"state"`
	SourceBranch string `json:"source_branch"`
	TargetBranch string `json:"target_branch"`
}

func GetMRs(url string) []MergeRequest {
	req, err := http.NewRequest(http.MethodGet, url, nil)
	if err != nil {
		log.Fatal("Failed to create request: ", err)
	}

	client := &http.Client{}

	res, err := client.Do(req)
	if err != nil {
		log.Fatal("Error checking MR status: ", err)
	}

	if res.StatusCode == 404 {
		log.Fatalf("No open merge request for this branch")
	}

	body, err := ioutil.ReadAll(res.Body)

	if err != nil {
		log.Fatal("Error reading response body: ", err)
	}

	var jsonData []MergeRequest
	err = json.Unmarshal(body, &jsonData)
	if err != nil {
		log.Fatal("Error unmarshaling JSON response: ", err)
	}

	return jsonData
}

func GetCurrentBranch() string {
	gitCmd := exec.Command("git", "rev-parse", "--abbrev-ref", "HEAD")

	output, err := gitCmd.Output()
	if err != nil {
		log.Fatalf("Error running git rev-parse: %s", err)
	}

	sourceBranch := strings.TrimSpace(string(output))
	return sourceBranch

}
